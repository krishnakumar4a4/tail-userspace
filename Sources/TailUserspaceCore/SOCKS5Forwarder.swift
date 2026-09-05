import Foundation
import Darwin

/// A lightweight, multi-client TCP-over-SOCKS5 forwarder
/// Bridges localhost:<localPort> to <remoteHost>:<remotePort> via tailscaled's SOCKS5 proxy
public final class SOCKS5Forwarder {
    public static let shared = SOCKS5Forwarder()

    private let lock = NSLock()
    private var activeListeners: [String: ForwarderInstance] = [:]

    public init() {}

    /// Starts forwarders for all enabled remote proxies in the configuration
    public func startConfiguredProxies(_ config: TailUserspaceConfig) {
        lock.lock()
        defer { lock.unlock() }

        // Stop forwarders no longer in config or disabled
        let activeIDs = Set(config.remoteProxies.filter { $0.enabled }.map { $0.id })
        for (id, instance) in activeListeners where !activeIDs.contains(id) {
            instance.stop()
            activeListeners.removeValue(forKey: id)
        }

        // Start new or updated forwarders
        for proxy in config.remoteProxies where proxy.enabled {
            if let existing = activeListeners[proxy.id] {
                if existing.proxy == proxy && existing.socks5Port == config.socks5Port {
                    continue // Already running with identical config
                }
                existing.stop()
                activeListeners.removeValue(forKey: proxy.id)
            }

            let instance = ForwarderInstance(proxy: proxy, socks5Port: config.socks5Port)
            do {
                try instance.start()
                activeListeners[proxy.id] = instance
            } catch {
                print("[SOCKS5Forwarder] Failed to bind proxy for \(proxy.remoteHost):\(proxy.remotePort) on port \(proxy.localPort): \(error)")
            }
        }
    }

    /// Stops all running forwarders
    public func stopAll() {
        lock.lock()
        defer { lock.unlock() }

        for (_, instance) in activeListeners {
            instance.stop()
        }
        activeListeners.removeAll()
    }

    /// Checks if a forwarder is active for a given proxy ID
    public func isProxyRunning(id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeListeners[id]?.isRunning ?? false
    }
}

/// Single TCP listener instance for a single remote proxy route
final class ForwarderInstance {
    let proxy: RemoteProxy
    let socks5Port: Int
    private(set) var isRunning: Bool = false

    private var serverFd: Int32 = -1
    private var queue: DispatchQueue
    private var isStopping: Bool = false

    init(proxy: RemoteProxy, socks5Port: Int) {
        self.proxy = proxy
        self.socks5Port = socks5Port
        self.queue = DispatchQueue(label: "dev.tailuserspace.proxy.\(proxy.localPort)", attributes: .concurrent)
    }

    func start() throws {
        serverFd = socket(AF_INET, SOCK_STREAM, 0)
        guard serverFd >= 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

        var opt: Int32 = 1
        setsockopt(serverFd, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(proxy.localPort).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindRes = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverFd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindRes == 0 else {
            close(serverFd)
            serverFd = -1
            throw POSIXError(.init(rawValue: errno) ?? .EADDRINUSE)
        }

        guard listen(serverFd, 128) == 0 else {
            close(serverFd)
            serverFd = -1
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

        isRunning = true
        isStopping = false

        // Background accept loop
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.acceptLoop()
        }
    }

    func stop() {
        isStopping = true
        isRunning = false
        if serverFd >= 0 {
            close(serverFd)
            serverFd = -1
        }
    }

    private func acceptLoop() {
        while isRunning && !isStopping {
            var clientAddr = sockaddr_in()
            var clientAddrLen = socklen_t(MemoryLayout<sockaddr_in>.size)

            let clientFd = withUnsafeMutablePointer(to: &clientAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    accept(serverFd, $0, &clientAddrLen)
                }
            }

            guard clientFd >= 0 else {
                if isStopping { break }
                usleep(50_000)
                continue
            }

            // Handle connection in background
            queue.async { [weak self] in
                self?.handleClient(clientFd: clientFd)
            }
        }
    }

    private func handleClient(clientFd: Int32) {
        defer { close(clientFd) }

        // 1. Connect to SOCKS5 proxy on 127.0.0.1:socks5Port
        let proxyFd = socket(AF_INET, SOCK_STREAM, 0)
        guard proxyFd >= 0 else { return }
        defer { close(proxyFd) }

        var proxyAddr = sockaddr_in()
        proxyAddr.sin_family = sa_family_t(AF_INET)
        proxyAddr.sin_port = in_port_t(socks5Port).bigEndian
        proxyAddr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let connRes = withUnsafePointer(to: &proxyAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(proxyFd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connRes == 0 else { return }

        // 2. Perform SOCKS5 greeting: [0x05, 0x01, 0x00] (VER 5, 1 Method, No Auth)
        var greeting: [UInt8] = [0x05, 0x01, 0x00]
        guard writeAll(fd: proxyFd, buffer: &greeting, count: greeting.count) else { return }

        var greetingResp: [UInt8] = [0, 0]
        guard readExact(fd: proxyFd, buffer: &greetingResp, count: 2),
              greetingResp[0] == 0x05, greetingResp[1] == 0x00 else {
            return
        }

        // 3. Send SOCKS5 CONNECT request
        // Format: [VER(5), CMD(1), RSV(0), ATYP(3=Domain/1=IPv4), ADDR..., PORT(2)]
        var req: [UInt8] = [0x05, 0x01, 0x00]
        let hostData = Array(proxy.remoteHost.utf8)

        let ipAddr = inet_addr(proxy.remoteHost)
        if ipAddr != INADDR_NONE {
            // IPv4
            req.append(0x01)
            var ip = ipAddr
            withUnsafeBytes(of: &ip) { req.append(contentsOf: $0) }
        } else {
            // Domain name
            req.append(0x03)
            req.append(UInt8(min(hostData.count, 255)))
            req.append(contentsOf: hostData.prefix(255))
        }

        let portNum = UInt16(proxy.remotePort).bigEndian
        withUnsafeBytes(of: portNum) { req.append(contentsOf: $0) }

        guard writeAll(fd: proxyFd, buffer: &req, count: req.count) else { return }

        // 4. Read response: [VER, REP, RSV, ATYP, BND.ADDR..., BND.PORT]
        var respHeader: [UInt8] = [0, 0, 0, 0]
        guard readExact(fd: proxyFd, buffer: &respHeader, count: 4) else { return }
        guard respHeader[0] == 0x05, respHeader[1] == 0x00 else {
            // SOCKS5 request rejected or failed
            return
        }

        // Consume address bytes of the response
        let atyp = respHeader[3]
        if atyp == 0x01 { // IPv4: 4 bytes + 2 bytes port
            var discard = [UInt8](repeating: 0, count: 6)
            _ = readExact(fd: proxyFd, buffer: &discard, count: 6)
        } else if atyp == 0x03 { // Domain: 1 byte len + domain + 2 bytes port
            var lenByte: UInt8 = 0
            _ = readExact(fd: proxyFd, buffer: &lenByte, count: 1)
            var discard = [UInt8](repeating: 0, count: Int(lenByte) + 2)
            _ = readExact(fd: proxyFd, buffer: &discard, count: discard.count)
        } else if atyp == 0x04 { // IPv6: 16 bytes + 2 bytes port
            var discard = [UInt8](repeating: 0, count: 18)
            _ = readExact(fd: proxyFd, buffer: &discard, count: 18)
        }

        // 5. Bidirectional splice/relay between clientFd and proxyFd
        splice(fdA: clientFd, fdB: proxyFd)
    }

    private func splice(fdA: Int32, fdB: Int32) {
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global().async { [self] in
            self.pipeStream(from: fdA, to: fdB)
            shutdown(fdB, SHUT_WR)
            group.leave()
        }

        group.enter()
        DispatchQueue.global().async { [self] in
            self.pipeStream(from: fdB, to: fdA)
            shutdown(fdA, SHUT_WR)
            group.leave()
        }

        group.wait()
    }

    private func pipeStream(from: Int32, to: Int32) {
        var buffer = [UInt8](repeating: 0, count: 16384)
        while true {
            let bytesRead = read(from, &buffer, buffer.count)
            guard bytesRead > 0 else { break }
            guard writeAll(fd: to, buffer: &buffer, count: bytesRead) else { break }
        }
    }

    private func writeAll(fd: Int32, buffer: UnsafeRawPointer, count: Int) -> Bool {
        var written = 0
        while written < count {
            let n = write(fd, buffer.advanced(by: written), count - written)
            if n <= 0 { return false }
            written += n
        }
        return true
    }

    private func readExact(fd: Int32, buffer: UnsafeMutableRawPointer, count: Int) -> Bool {
        var bytesRead = 0
        while bytesRead < count {
            let n = read(fd, buffer.advanced(by: bytesRead), count - bytesRead)
            if n <= 0 { return false }
            bytesRead += n
        }
        return true
    }
}
