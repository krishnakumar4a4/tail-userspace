import Foundation

/// Full-featured Model Context Protocol (MCP) server communicating over JSON-RPC 2.0
public final class MCPServer: @unchecked Sendable {
    public static let shared = MCPServer()

    private let client: TailscaleClient
    private let supervisor: DaemonSupervisor
    private let configManager: ConfigManager
    private let forwarder: SOCKS5Forwarder

    private let stateLock = NSLock()
    private var isInitialized: Bool = false

    public init(
        client: TailscaleClient = .shared,
        supervisor: DaemonSupervisor = .shared,
        configManager: ConfigManager = .shared,
        forwarder: SOCKS5Forwarder = .shared
    ) {
        self.client = client
        self.supervisor = supervisor
        self.configManager = configManager
        self.forwarder = forwarder
    }

    /// Processes a single raw incoming JSON-RPC message line and returns the response Data (if any)
    public func handleMessageData(_ data: Data) -> Data? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let err = MCPProtocol.makeError(id: nil, code: MCPProtocol.parseError, message: "Parse error: Invalid JSON")
            return try? JSONSerialization.data(withJSONObject: err)
        }

        let id = json["id"]
        guard let method = json["method"] as? String else {
            if id != nil {
                let err = MCPProtocol.makeError(id: id, code: MCPProtocol.invalidRequest, message: "Invalid Request: 'method' field is required")
                return try? JSONSerialization.data(withJSONObject: err)
            }
            return nil
        }

        let params = json["params"] as? [String: Any] ?? [:]
        let isNotification = (id == nil || id is NSNull)

        switch method {
        case "initialize":
            stateLock.lock()
            isInitialized = true
            stateLock.unlock()

            let result: [String: Any] = [
                "protocolVersion": MCPProtocol.protocolVersion,
                "capabilities": [
                    "tools": [
                        "listChanged": false
                    ],
                    "resources": [
                        "subscribe": false,
                        "listChanged": false
                    ],
                    "prompts": [
                        "listChanged": false
                    ]
                ],
                "serverInfo": [
                    "name": MCPProtocol.serverName,
                    "version": MCPProtocol.serverVersion
                ]
            ]
            let resp = MCPProtocol.makeResponse(id: id ?? 1, result: result)
            return try? JSONSerialization.data(withJSONObject: resp)

        case "notifications/initialized":
            stateLock.lock()
            isInitialized = true
            stateLock.unlock()
            return nil // Notifications do not generate a response

        case "ping":
            if isNotification { return nil }
            let resp = MCPProtocol.makeResponse(id: id!, result: [:] as [String: Any])
            return try? JSONSerialization.data(withJSONObject: resp)

        case "tools/list":
            if isNotification { return nil }
            let toolsDict = MCPTools.allTools.map { $0.asDictionary() }
            let resp = MCPProtocol.makeResponse(id: id!, result: ["tools": toolsDict])
            return try? JSONSerialization.data(withJSONObject: resp)

        case "tools/call":
            if isNotification { return nil }
            guard let toolName = params["name"] as? String else {
                let err = MCPProtocol.makeError(id: id!, code: MCPProtocol.invalidParams, message: "Missing required param 'name'")
                return try? JSONSerialization.data(withJSONObject: err)
            }
            let args = params["arguments"] as? [String: Any] ?? [:]

            do {
                let output = try MCPTools.execute(
                    name: toolName,
                    arguments: args,
                    client: client,
                    supervisor: supervisor,
                    configManager: configManager,
                    forwarder: forwarder
                )
                let result: [String: Any] = [
                    "content": [
                        [
                            "type": "text",
                            "text": output
                        ]
                    ],
                    "isError": false
                ]
                let resp = MCPProtocol.makeResponse(id: id!, result: result)
                return try? JSONSerialization.data(withJSONObject: resp)
            } catch {
                let result: [String: Any] = [
                    "content": [
                        [
                            "type": "text",
                            "text": "Tool '\(toolName)' failed: \(error.localizedDescription)"
                        ]
                    ],
                    "isError": true
                ]
                let resp = MCPProtocol.makeResponse(id: id!, result: result)
                return try? JSONSerialization.data(withJSONObject: resp)
            }

        case "resources/list":
            if isNotification { return nil }
            let resourcesDict = MCPResources.allResources.map { $0.asDictionary() }
            let resp = MCPProtocol.makeResponse(id: id!, result: ["resources": resourcesDict])
            return try? JSONSerialization.data(withJSONObject: resp)

        case "resources/read":
            if isNotification { return nil }
            guard let uri = params["uri"] as? String else {
                let err = MCPProtocol.makeError(id: id!, code: MCPProtocol.invalidParams, message: "Missing required param 'uri'")
                return try? JSONSerialization.data(withJSONObject: err)
            }

            do {
                let (text, mime) = try MCPResources.read(
                    uri: uri,
                    client: client,
                    supervisor: supervisor,
                    configManager: configManager,
                    forwarder: forwarder
                )
                let result: [String: Any] = [
                    "contents": [
                        [
                            "uri": uri,
                            "mimeType": mime,
                            "text": text
                        ]
                    ]
                ]
                let resp = MCPProtocol.makeResponse(id: id!, result: result)
                return try? JSONSerialization.data(withJSONObject: resp)
            } catch {
                let err = MCPProtocol.makeError(id: id!, code: MCPProtocol.invalidParams, message: error.localizedDescription)
                return try? JSONSerialization.data(withJSONObject: err)
            }

        case "prompts/list":
            if isNotification { return nil }
            let promptsDict = MCPPrompts.allPrompts.map { $0.asDictionary() }
            let resp = MCPProtocol.makeResponse(id: id!, result: ["prompts": promptsDict])
            return try? JSONSerialization.data(withJSONObject: resp)

        case "prompts/get":
            if isNotification { return nil }
            guard let promptName = params["name"] as? String else {
                let err = MCPProtocol.makeError(id: id!, code: MCPProtocol.invalidParams, message: "Missing required param 'name'")
                return try? JSONSerialization.data(withJSONObject: err)
            }
            let args = params["arguments"] as? [String: Any] ?? [:]

            do {
                let (desc, messages) = try MCPPrompts.get(
                    name: promptName,
                    arguments: args,
                    client: client,
                    supervisor: supervisor,
                    configManager: configManager
                )
                let result: [String: Any] = [
                    "description": desc,
                    "messages": messages
                ]
                let resp = MCPProtocol.makeResponse(id: id!, result: result)
                return try? JSONSerialization.data(withJSONObject: resp)
            } catch {
                let err = MCPProtocol.makeError(id: id!, code: MCPProtocol.invalidParams, message: error.localizedDescription)
                return try? JSONSerialization.data(withJSONObject: err)
            }

        default:
            if isNotification { return nil }
            let err = MCPProtocol.makeError(id: id!, code: MCPProtocol.methodNotFound, message: "Method '\(method)' not found")
            return try? JSONSerialization.data(withJSONObject: err)
        }
    }

    /// Runs the message loop on input and output file handles until EOF
    public func run(inputHandle: FileHandle, outputHandle: FileHandle) {
        var buffer = Data()
        let newlineByte = UInt8(0x0A) // '\n'

        while true {
            let chunk = inputHandle.availableData
            if chunk.isEmpty {
                // EOF reached on input
                break
            }
            buffer.append(chunk)

            while let newlineIndex = buffer.firstIndex(of: newlineByte) {
                let lineData = buffer.subdata(in: 0..<newlineIndex)
                buffer.removeSubrange(0...newlineIndex)

                // Skip blank lines
                guard !lineData.isEmpty else { continue }

                if let responseData = handleMessageData(lineData) {
                    var out = responseData
                    out.append(newlineByte)
                    outputHandle.write(out)
                }
            }
        }
    }

    /// Starts stdio-based MCP server (reads stdin, writes stdout)
    public func runStdio() {
        // Direct all logging to stderr so stdout remains 100% pure JSON-RPC
        Logger.shared.useStderr = true
        Logger.shared.info("Starting TailUserspace MCP server on stdio...")

        // Handle termination signals gracefully
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)

        let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
        sigint.setEventHandler {
            Logger.shared.info("MCP server received SIGINT. Exiting...")
            exit(0)
        }
        sigint.resume()

        let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
        sigterm.setEventHandler {
            Logger.shared.info("MCP server received SIGTERM. Exiting...")
            exit(0)
        }
        sigterm.resume()

        run(inputHandle: .standardInput, outputHandle: .standardOutput)
    }
}
