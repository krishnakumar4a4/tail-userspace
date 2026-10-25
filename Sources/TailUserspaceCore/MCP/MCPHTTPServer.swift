import Foundation
import Darwin

/// Embedded HTTP and SSE server implementing Model Context Protocol (MCP) remote transport
public final class MCPHTTPServer: @unchecked Sendable {
    public static let shared = MCPHTTPServer()

    private let lock = NSLock()
    private var serverFd: Int32 = -1
    public private(set) var port: Int = 1058
    public private(set) var isRunning: Bool = false
    private var isStopping: Bool = false

    // Maps sessionId -> client socket file descriptor for active SSE streaming connections
    private var activeSessions: [String: Int32] = [:]
    private let mcpServer: MCPServer

    public init(mcpServer: MCPServer = .shared) {
        self.mcpServer = mcpServer
    }

    /// Starts the HTTP server on 127.0.0.1:<port>
    public func start(port: Int = 1058) throws {
        lock.lock()
        if isRunning {
            if self.port == port {
                lock.unlock()
                return
            }
            // Stop old port to switch to new port
            stopLocked()
        }

        self.port = port
        self.isStopping = false

        serverFd = socket(AF_INET, SOCK_STREAM, 0)
        guard serverFd >= 0 else {
            lock.unlock()
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

        var opt: Int32 = 1
        setsockopt(serverFd, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(serverFd, SOL_SOCKET, SO_NOSIGPIPE, &opt, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindRes = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverFd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindRes == 0 else {
            let err = errno
            close(serverFd)
            serverFd = -1
            lock.unlock()
            throw POSIXError(.init(rawValue: err) ?? .EADDRINUSE)
        }

        guard listen(serverFd, 64) == 0 else {
            let err = errno
            close(serverFd)
            serverFd = -1
            lock.unlock()
            throw POSIXError(.init(rawValue: err) ?? .EIO)
        }

        isRunning = true
        lock.unlock()

        Logger.shared.info("MCP HTTP Server successfully listening on http://127.0.0.1:\(port)")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.acceptLoop()
        }
    }

    /// Stops the HTTP server and terminates active sessions
    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        stopLocked()
    }

    private func stopLocked() {
        isStopping = true
        isRunning = false

        if serverFd >= 0 {
            close(serverFd)
            serverFd = -1
        }

        for (_, fd) in activeSessions {
            close(fd)
        }
        activeSessions.removeAll()
    }

    private func acceptLoop() {
        while isRunning && !isStopping {
            var clientAddr = sockaddr_in()
            var clientLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let clientFd = withUnsafeMutablePointer(to: &clientAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    accept(serverFd, $0, &clientLen)
                }
            }

            guard clientFd >= 0 else {
                if isStopping || !isRunning { break }
                usleep(10_000)
                continue
            }

            var opt: Int32 = 1
            setsockopt(clientFd, SOL_SOCKET, SO_NOSIGPIPE, &opt, socklen_t(MemoryLayout<Int32>.size))

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.handleConnection(clientFd)
            }
        }
    }

    private func handleConnection(_ fd: Int32) {
        // Set read timeout for header reading
        var timeout = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        var headerEndIndex: Int? = nil

        while headerEndIndex == nil {
            let bytesRead = read(fd, &chunk, chunk.count)
            guard bytesRead > 0 else {
                close(fd)
                return
            }
            buffer.append(chunk, count: bytesRead)

            if let range = buffer.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) { // \r\n\r\n
                headerEndIndex = range.upperBound
                break
            } else if let range = buffer.range(of: Data([0x0A, 0x0A])) { // \n\n fallback
                headerEndIndex = range.upperBound
                break
            }
        }

        guard let headerEnd = headerEndIndex,
              let headerString = String(data: buffer.subdata(in: 0..<headerEnd), encoding: .utf8) else {
            sendResponse(fd: fd, status: 400, body: "Bad Request: Invalid HTTP headers")
            close(fd)
            return
        }

        let headerLines = headerString.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard let requestLine = headerLines.first else {
            close(fd)
            return
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            sendResponse(fd: fd, status: 400, body: "Bad Request: Invalid Request-Line")
            close(fd)
            return
        }

        let method = String(parts[0]).uppercased()
        let rawUri = String(parts[1])

        var headers: [String: String] = [:]
        for line in headerLines.dropFirst() {
            let pair = line.split(separator: ":", maxSplits: 1)
            if pair.count == 2 {
                let key = String(pair[0]).trimmingCharacters(in: .whitespaces).lowercased()
                let val = String(pair[1]).trimmingCharacters(in: .whitespaces)
                headers[key] = val
            }
        }

        let uriParts = rawUri.split(separator: "?", maxSplits: 1)
        let path = String(uriParts[0])
        var queryParams: [String: String] = [:]
        if uriParts.count == 2 {
            for q in uriParts[1].split(separator: "&") {
                let kv = q.split(separator: "=", maxSplits: 1)
                if kv.count == 2 {
                    let k = String(kv[0])
                    let v = String(kv[1]).removingPercentEncoding ?? String(kv[1])
                    queryParams[k] = v
                }
            }
        }

        let contentLength = Int(headers["content-length"] ?? "") ?? 0

        // Read body if Content-Length > 0
        let bodyStartIndex = headerEnd
        let existingBodyBytes = buffer.count - bodyStartIndex
        var remainingToRead = contentLength - existingBodyBytes
        while remainingToRead > 0 {
            let bytesRead = read(fd, &chunk, min(chunk.count, remainingToRead))
            guard bytesRead > 0 else { break }
            buffer.append(chunk, count: bytesRead)
            remainingToRead -= bytesRead
        }

        let bodyData = buffer.subdata(in: bodyStartIndex..<min(buffer.count, bodyStartIndex + contentLength))

        // 1. CORS Preflight
        if method == "OPTIONS" {
            sendCORSPreflight(fd: fd)
            close(fd)
            return
        }

        // 2. Server-Sent Events (SSE) Transport (GET /sse or Accept: text/event-stream)
        if method == "GET" && (path == "/sse" || (headers["accept"] ?? "").contains("text/event-stream")) {
            handleSSEStream(fd: fd)
            return // fd is kept open by handleSSEStream
        }

        // 3. SSE Postback messages endpoint (POST /messages or POST /message)
        if method == "POST" && (path == "/messages" || path == "/message") {
            let sessionId = queryParams["sessionId"] ?? headers["x-session-id"]
            handleMessagePost(fd: fd, body: bodyData, sessionId: sessionId)
            close(fd)
            return
        }

        // 4. Direct JSON-RPC over HTTP POST (POST /mcp or POST /)
        if method == "POST" && (path == "/mcp" || path == "/" || path == "/jsonrpc") {
            handleDirectJSONRPC(fd: fd, body: bodyData)
            close(fd)
            return
        }

        // 5. Friendly GET status endpoint (GET / or GET /mcp or GET /status)
        if method == "GET" && (path == "/" || path == "/mcp" || path == "/status") {
            handleStatusInfo(fd: fd)
            close(fd)
            return
        }

        // 6. Unknown Endpoint
        sendResponse(fd: fd, status: 404, contentType: "application/json", body: "{\"error\":\"Endpoint not found\"}")
        close(fd)
    }

    private func handleDirectJSONRPC(fd: Int32, body: Data) {
        if let responseData = mcpServer.handleMessageData(body) {
            sendResponseData(fd: fd, status: 200, contentType: "application/json", data: responseData)
        } else {
            // Notification or empty response
            sendResponse(fd: fd, status: 204, body: "")
        }
    }

    private func handleMessagePost(fd: Int32, body: Data, sessionId: String?) {
        guard let responseData = mcpServer.handleMessageData(body) else {
            sendResponse(fd: fd, status: 202, body: "")
            return
        }

        let respStr = String(data: responseData, encoding: .utf8) ?? "{}"

        // If an active SSE session exists for this sessionId, send event over SSE stream
        if let sid = sessionId {
            lock.lock()
            let sseFd = activeSessions[sid]
            lock.unlock()

            if let sseFd = sseFd {
                let eventStr = "event: message\ndata: \(respStr)\n\n"
                if let eventData = eventStr.data(using: .utf8) {
                    _ = eventData.withUnsafeBytes { ptr in
                        write(sseFd, ptr.baseAddress, eventData.count)
                    }
                }
            }
        }

        // Also return the JSON-RPC response directly in HTTP POST body (dual-transport compatibility)
        sendResponseData(fd: fd, status: 200, contentType: "application/json", data: responseData)
    }

    private func handleSSEStream(fd: Int32) {
        // Clear read timeout for long-lived SSE connection
        var zeroTimeout = timeval(tv_sec: 0, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &zeroTimeout, socklen_t(MemoryLayout<timeval>.size))

        let sessionId = UUID().uuidString
        lock.lock()
        activeSessions[sessionId] = fd
        lock.unlock()

        let headers = """
        HTTP/1.1 200 OK\r
        Content-Type: text/event-stream\r
        Cache-Control: no-cache, no-transform\r
        Connection: keep-alive\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Headers: Content-Type, Authorization, x-session-id\r
        \r

        """

        let initialEvent = """
        event: endpoint\r
        data: /messages?sessionId=\(sessionId)\r
        \r

        """

        writeAll(fd: fd, string: headers)
        writeAll(fd: fd, string: initialEvent)

        // Keep-alive loop until client disconnects or server stops
        while isRunning && !isStopping {
            sleep(15)
            let ping = ": keepalive\n\n"
            if !writeAll(fd: fd, string: ping) {
                break
            }
        }

        lock.lock()
        activeSessions.removeValue(forKey: sessionId)
        lock.unlock()
        close(fd)
    }

    private func handleStatusInfo(fd: Int32) {
        let statusObj: [String: Any] = [
            "status": "online",
            "name": "tail-userspace",
            "transport": "HTTP & Server-Sent Events (SSE)",
            "protocolVersion": MCPProtocol.protocolVersion,
            "serverVersion": MCPProtocol.serverVersion,
            "endpoints": [
                "mcp": "http://127.0.0.1:\(port)/mcp",
                "sse": "http://127.0.0.1:\(port)/sse",
                "messages": "http://127.0.0.1:\(port)/messages"
            ],
            "description": "TailUserspace Model Context Protocol (MCP) HTTP interface for AI coding assistants"
        ]
        let data = (try? JSONSerialization.data(withJSONObject: statusObj, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        sendResponseData(fd: fd, status: 200, contentType: "application/json", data: data)
    }

    private func sendCORSPreflight(fd: Int32) {
        let resp = """
        HTTP/1.1 204 No Content\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: GET, POST, OPTIONS, HEAD\r
        Access-Control-Allow-Headers: Content-Type, Authorization, x-session-id\r
        Access-Control-Max-Age: 86400\r
        Content-Length: 0\r
        Connection: close\r
        \r

        """
        writeAll(fd: fd, string: resp)
    }

    private func sendResponse(fd: Int32, status: Int, contentType: String = "text/plain", body: String) {
        let data = body.data(using: .utf8) ?? Data()
        sendResponseData(fd: fd, status: status, contentType: contentType, data: data)
    }

    private func sendResponseData(fd: Int32, status: Int, contentType: String = "application/json", data: Data) {
        let statusText = status == 200 ? "OK" : status == 204 ? "No Content" : status == 400 ? "Bad Request" : status == 404 ? "Not Found" : "Error"
        let header = """
        HTTP/1.1 \(status) \(statusText)\r
        Content-Type: \(contentType)\r
        Content-Length: \(data.count)\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Headers: Content-Type, Authorization, x-session-id\r
        Connection: close\r
        \r

        """
        writeAll(fd: fd, string: header)
        _ = data.withUnsafeBytes { ptr in
            write(fd, ptr.baseAddress, data.count)
        }
    }

    @discardableResult
    private func writeAll(fd: Int32, string: String) -> Bool {
        guard let data = string.data(using: .utf8) else { return false }
        var written = 0
        while written < data.count {
            let res = data.withUnsafeBytes { ptr -> Int in
                let base = ptr.baseAddress?.advanced(by: written)
                return write(fd, base, data.count - written)
            }
            if res <= 0 { return false }
            written += res
        }
        return true
    }
}
