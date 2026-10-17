import Foundation

public enum TailscaleClientError: LocalizedError {
    case tailscaleCLINotFound
    case commandFailed(command: String, code: Int32, errorOutput: String)
    case jsonParsingFailed(String)
    case daemonNotRunning

    public var errorDescription: String? {
        switch self {
        case .tailscaleCLINotFound:
            return "Could not find 'tailscale' CLI binary. Please ensure Tailscale is installed."
        case .commandFailed(let cmd, let code, let err):
            return "Command '\(cmd)' failed (exit code \(code)): \(err)"
        case .jsonParsingFailed(let msg):
            return "Failed to parse Tailscale JSON response: \(msg)"
        case .daemonNotRunning:
            return "Tailscale daemon is not running."
        }
    }
}

/// Client interacting with the userspace tailscaled socket via tailscale CLI commands
public final class TailscaleClient {
    public static let shared = TailscaleClient()

    public init() {}

    /// Locates the tailscale CLI executable
    public static func findTailscaleCLI() -> String? {
        if let custom = ProcessInfo.processInfo.environment["TAILSCALE_CLI_PATH"], FileManager.default.isExecutableFile(atPath: custom) {
            return custom
        }
        let candidates = [
            "/opt/homebrew/bin/tailscale",
            "/usr/local/bin/tailscale",
            "/usr/bin/tailscale"
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        let whichProcess = Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = ["tailscale"]
        let pipe = Pipe()
        whichProcess.standardOutput = pipe
        try? whichProcess.run()
        whichProcess.waitUntilExit()
        if whichProcess.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty {
                return output
            }
        }
        return nil
    }

    /// Runs a tailscale CLI subcommand pointing to our custom socket
    @discardableResult
    public func runCommand(_ args: [String], timeout: TimeInterval = 15.0) throws -> String {
        guard let cli = Self.findTailscaleCLI() else {
            throw TailscaleClientError.tailscaleCLINotFound
        }

        var fullArgs = ["--socket=\(PathConstants.socketPath)"]
        fullArgs.append(contentsOf: args)

        Logger.shared.info("Executing: \(cli) \(fullArgs.joined(separator: " "))")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cli)
        process.arguments = fullArgs

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let startTime = Date()
        try process.run()

        // Wait with timeout
        while process.isRunning && Date().timeIntervalSince(startTime) < timeout {
            usleep(50_000) // 50ms
        }
        if process.isRunning {
            process.terminate()
            Logger.shared.debug("Command timed out after \(timeout)s: \(args.joined(separator: " "))")
            throw TailscaleClientError.commandFailed(
                command: args.joined(separator: " "),
                code: -1,
                errorOutput: "Command timed out after \(timeout)s"
            )
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        let stdoutStr = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderrStr = String(data: stderrData, encoding: .utf8) ?? ""
        let duration = Date().timeIntervalSince(startTime)

        Logger.shared.debug("Command exited with code \(process.terminationStatus) in \(String(format: "%.3f", duration))s")
        if !stdoutStr.isEmpty {
            Logger.shared.trace("stdout:\n\(stdoutStr)")
        }
        if !stderrStr.isEmpty {
            Logger.shared.trace("stderr:\n\(stderrStr)")
        }

        if process.terminationStatus != 0 {
            throw TailscaleClientError.commandFailed(
                command: args.joined(separator: " "),
                code: process.terminationStatus,
                errorOutput: stderrStr.isEmpty ? stdoutStr : stderrStr
            )
        }

        return stdoutStr
    }

    /// Fetches live status of the daemon
    public func getStatus() -> DaemonStatus {
        let (running, pid) = DaemonSupervisor.shared.isRunning()
        guard running else {
            return DaemonStatus(isProcessRunning: false, pid: nil, backendState: "NoDaemon")
        }

        guard FileManager.default.fileExists(atPath: PathConstants.socketPath) else {
            return DaemonStatus(isProcessRunning: true, pid: pid, backendState: "Starting")
        }

        do {
            let jsonString = try runCommand(["status", "--json"], timeout: 5.0)
            guard let data = jsonString.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return DaemonStatus(isProcessRunning: true, pid: pid, backendState: "Unknown")
            }

            let backendState = json["BackendState"] as? String ?? "Unknown"
            let authURL = json["AuthURL"] as? String
            let health = json["Health"] as? [String] ?? []
            let selfNode = json["Self"] as? [String: Any] ?? [:]
            let selfName = selfNode["HostName"] as? String ?? ""
            let selfDNSName = selfNode["DNSName"] as? String ?? ""
            let tailscaleIPs = json["TailscaleIPs"] as? [String] ?? []

            return DaemonStatus(
                isProcessRunning: true,
                pid: pid,
                backendState: backendState,
                selfName: selfName,
                selfDNSName: selfDNSName.trimmingCharacters(in: CharacterSet(charactersIn: ".")),
                tailscaleIPs: tailscaleIPs,
                authURL: authURL,
                healthWarnings: health
            )
        } catch {
            return DaemonStatus(isProcessRunning: true, pid: pid, backendState: "Error", healthWarnings: [error.localizedDescription])
        }
    }

    // MARK: - Connection Controls

    /// Connects to the tailnet, streaming real-time output and detecting Auth URLs
    public func connect(
        extraArgs: [String] = [],
        timeout: TimeInterval = 180.0,
        autoOpenBrowser: Bool = true,
        onAuthURL: ((URL) -> Void)? = nil,
        onOutput: ((String) -> Void)? = nil
    ) throws {
        // Ensure daemon is started
        let (running, _) = DaemonSupervisor.shared.isRunning()
        if !running {
            Logger.shared.info("Tailscale userspace daemon is not running. Starting...")
            _ = try DaemonSupervisor.shared.start()
        }

        guard let cli = Self.findTailscaleCLI() else {
            throw TailscaleClientError.tailscaleCLINotFound
        }

        var fullArgs = ["--socket=\(PathConstants.socketPath)", "up"]
        fullArgs.append(contentsOf: extraArgs)

        Logger.shared.info("Executing: \(cli) \(fullArgs.joined(separator: " "))")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cli)
        process.arguments = fullArgs

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let lock = NSLock()
        var authURLHandled = false
        var accumulatedOutput = ""

        func processIncomingText(_ text: String) {
            lock.lock()
            accumulatedOutput += text
            lock.unlock()

            onOutput?(text)
            Logger.shared.trace("stream: \(text)")

            // Look for auth URL in stream
            if !authURLHandled {
                let pattern = #"https://login\.tailscale\.com/[^\s)]+"#
                if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                   let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)),
                   let range = Range(match.range, in: text) {
                    let rawURL = String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:\"'<>[]()"))
                    if let url = URL(string: rawURL) {
                        lock.lock()
                        authURLHandled = true
                        lock.unlock()

                        onAuthURL?(url)
                        if autoOpenBrowser {
                            Self.openInBrowser(url)
                        }
                    }
                }
            }
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
            processIncomingText(str)
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
            processIncomingText(str)
        }

        let startTime = Date()
        try process.run()

        // Wait with timeout, while also checking status periodically for AuthURL
        while process.isRunning && Date().timeIntervalSince(startTime) < timeout {
            if !authURLHandled {
                let st = getStatus()
                if let authStr = st.authURL, let url = URL(string: authStr) {
                    lock.lock()
                    authURLHandled = true
                    lock.unlock()

                    onAuthURL?(url)
                    if autoOpenBrowser {
                        Self.openInBrowser(url)
                    }
                }
            }
            usleep(150_000) // 150ms
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        if process.isRunning {
            process.terminate()
            Logger.shared.debug("tailscale up process terminated after timeout (\(timeout)s)")
            throw TailscaleClientError.commandFailed(
                command: "up",
                code: -1,
                errorOutput: "Authentication / connection timed out after \(Int(timeout))s. Please re-run 'tail-userspace up' or check 'tail-userspace status'."
            )
        }

        let duration = Date().timeIntervalSince(startTime)
        Logger.shared.debug("tailscale up completed with exit code \(process.terminationStatus) in \(String(format: "%.2f", duration))s")

        if process.terminationStatus != 0 {
            throw TailscaleClientError.commandFailed(
                command: "up",
                code: process.terminationStatus,
                errorOutput: accumulatedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    /// Automatically opens URL in default macOS web browser
    public static func openInBrowser(_ url: URL) {
        Logger.shared.info("Opening browser for login URL: \(url.absoluteString)")
        let openProcess = Process()
        openProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        openProcess.arguments = [url.absoluteString]
        try? openProcess.run()
    }

    public func disconnect() throws {
        try runCommand(["down"])
    }

    // MARK: - Tailscale Serve Management

    /// Applies an Inbound Serve route: exposes a local port, URL, socket, or file to the tailnet
    public func applyServeRoute(_ route: ServeRoute, background: Bool = true) throws {
        var args = ["serve"]
        if background {
            args.append("--bg")
        }

        if route.proto == "https" {
            args.append("--https=\(route.servePort)")
        } else if route.proto == "http" {
            args.append("--http=\(route.servePort)")
        } else if route.proto == "tcp" {
            args.append("--tcp=\(route.servePort)")
        } else if route.proto == "tls-terminated-tcp" {
            args.append("--tls-terminated-tcp=\(route.servePort)")
        }

        if route.proto == "https" || route.proto == "http" {
            let path = route.path.isEmpty ? "/" : route.path
            if path != "/" {
                args.append("--set-path=\(path)")
            }
        }

        if let pp = route.proxyProtocol, (1...2).contains(pp) {
            args.append("--proxy-protocol=\(pp)")
        }

        args.append(route.target)

        try runCommand(args)
    }

    /// Turns off a specific serve route on the live daemon without resetting other routes
    public func removeServeRouteLive(_ route: ServeRoute) throws {
        var args = ["serve"]
        if route.proto == "http" {
            args.append("--http=\(route.servePort)")
        } else if route.proto == "tcp" {
            args.append("--tcp=\(route.servePort)")
        } else if route.proto == "tls-terminated-tcp" {
            args.append("--tls-terminated-tcp=\(route.servePort)")
        } else {
            args.append("--https=\(route.servePort)")
        }

        if route.proto == "https" || route.proto == "http" {
            let path = route.path.isEmpty ? "/" : route.path
            if path != "/" {
                args.append("--set-path=\(path)")
            }
        }

        args.append("off")
        do {
            _ = try runCommand(args)
        } catch {
            // Fallback: if specific path off failed, attempt with explicit set-path=/ if path was /
            if (route.proto == "https" || route.proto == "http") && route.path == "/" {
                var fallbackArgs = ["serve"]
                fallbackArgs.append(route.proto == "http" ? "--http=\(route.servePort)" : "--https=\(route.servePort)")
                fallbackArgs.append("--set-path=/")
                fallbackArgs.append("off")
                _ = try? runCommand(fallbackArgs)
            }
        }
    }

    /// Cleans up any ephemeral sessions whose CLI processes have terminated, unmounting them from the daemon
    @discardableResult
    public func cleanupStaleEphemeralSessionsAndUnmount() -> [EphemeralServeSession] {
        let all = ConfigManager.shared.loadEphemeralSessions()
        var alive: [EphemeralServeSession] = []
        for s in all {
            if kill(s.pid, 0) == 0 {
                alive.append(s)
            } else {
                _ = try? removeServeRouteLive(s.route)
                _ = try? ConfigManager.shared.removeEphemeralSession(id: s.id)
            }
        }
        return alive
    }

    /// Resets all Tailscale Serve configurations on the node
    public func resetServe() throws {
        try runCommand(["serve", "reset"])
    }

    /// Reads and applies all enabled serve routes from the config
    public func reapplyConfiguredServeRoutes(_ config: TailUserspaceConfig) throws {
        let status = getStatus()
        guard status.isOnline else { return }

        for route in config.serveRoutes where route.enabled {
            try? applyServeRoute(route)
        }
    }

    /// Returns human-readable or JSON serve status from live daemon
    public func getServeStatus(json: Bool = false) -> String {
        let args = json ? ["serve", "status", "--json"] : ["serve", "status"]
        return (try? runCommand(args)) ?? "No active serve endpoints"
    }

    /// Checks for discrepancies between persistent config and live daemon serve state
    public func checkServeDiscrepancies(config: TailUserspaceConfig) -> [ServeDiscrepancy] {
        var discrepancies: [ServeDiscrepancy] = []
        let status = getStatus()
        guard status.isOnline else {
            for route in config.serveRoutes where route.enabled {
                discrepancies.append(ServeDiscrepancy(
                    kind: .notOnDaemon,
                    route: route,
                    message: "Daemon is currently offline"
                ))
            }
            return discrepancies
        }

        var liveHandlers: [String: String] = [:]
        var liveTCPPorts: [Int: String] = [:]

        if let jsonStr = try? runCommand(["serve", "status", "--json"], timeout: 4.0),
           let data = jsonStr.data(using: .utf8),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

            if let web = root["Web"] as? [String: [String: Any]] {
                for (hostPort, webObj) in web {
                    let portStr = hostPort.split(separator: ":").last.map(String.init) ?? "443"
                    let servePort = Int(portStr) ?? 443
                    if let handlers = webObj["Handlers"] as? [String: [String: Any]] {
                        for (pathKey, handlerObj) in handlers {
                            let proxyTarget = (handlerObj["Proxy"] as? String) ?? (handlerObj["Text"] as? String) ?? ""
                            let key = "\(servePort):\(pathKey)"
                            liveHandlers[key] = proxyTarget
                        }
                    }
                }
            }

            if let tcp = root["TCP"] as? [String: [String: Any]] {
                for (portStr, tcpObj) in tcp {
                    if let port = Int(portStr) {
                        let proto = (tcpObj["HTTPS"] as? Bool == true) ? "https" :
                                    (tcpObj["HTTP"] as? Bool == true) ? "http" :
                                    (tcpObj["TLS"] as? Bool == true) ? "tls-terminated-tcp" : "tcp"
                        liveTCPPorts[port] = proto
                    }
                }
            }
        }

        let activeEphemeral = cleanupStaleEphemeralSessionsAndUnmount()

        // 1. Inspect configured routes
        for route in config.serveRoutes {
            if !route.enabled { continue }

            let pathKey = "\(route.servePort):\(route.path)"
            if route.proto == "https" || route.proto == "http" {
                if let liveTarget = liveHandlers[pathKey] {
                    let isMatch = targetsMatch(routeTarget: route.target, liveTarget: liveTarget)
                    if isMatch {
                        discrepancies.append(ServeDiscrepancy(
                            kind: .inSync,
                            route: route,
                            liveTarget: liveTarget,
                            message: "Route is active and in sync with live daemon."
                        ))
                    } else {
                        discrepancies.append(ServeDiscrepancy(
                            kind: .mismatch,
                            route: route,
                            liveTarget: liveTarget,
                            message: "Target mismatch: config has '\(route.target)', live daemon has '\(liveTarget)'."
                        ))
                    }
                } else {
                    discrepancies.append(ServeDiscrepancy(
                        kind: .notOnDaemon,
                        route: route,
                        liveTarget: nil,
                        message: "Configured route '\(route.target)' on path '\(route.path)' is not running on live daemon."
                    ))
                }
            } else {
                if let _ = liveTCPPorts[route.servePort] {
                    discrepancies.append(ServeDiscrepancy(
                        kind: .inSync,
                        route: route,
                        liveTarget: "\(route.target) (TCP)",
                        message: "TCP port \(route.servePort) forwarding is active on daemon."
                    ))
                } else {
                    discrepancies.append(ServeDiscrepancy(
                        kind: .notOnDaemon,
                        route: route,
                        message: "TCP port \(route.servePort) is not running on live daemon."
                    ))
                }
            }
        }

        // 2. Check for live daemon handlers not in persistent config
        for (key, liveTarget) in liveHandlers {
            let parts = key.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, let servePort = Int(parts[0]) else { continue }
            let path = String(parts[1])

            let isConfigured = config.serveRoutes.contains {
                $0.enabled && $0.servePort == servePort && $0.path == path
            }
            if !isConfigured {
                if let eph = activeEphemeral.first(where: { $0.route.servePort == servePort && $0.route.path == path }) {
                    discrepancies.append(ServeDiscrepancy(
                        kind: .cliEphemeral,
                        route: eph.route,
                        liveTarget: liveTarget,
                        message: "Ephemeral session active from terminal CLI (PID: \(eph.pid))."
                    ))
                } else {
                    let unmanaged = ServeRoute(target: liveTarget, servePort: servePort, proto: "https", path: path)
                    discrepancies.append(ServeDiscrepancy(
                        kind: .daemonOnly,
                        route: unmanaged,
                        liveTarget: liveTarget,
                        message: "Active on live daemon, but unmanaged in config.json."
                    ))
                }
            }
        }

        return discrepancies
    }

    private func targetsMatch(routeTarget: String, liveTarget: String) -> Bool {
        if routeTarget == liveTarget { return true }
        if let p = Int(routeTarget) {
            return liveTarget.contains(":\(p)")
        }
        let normRoute = routeTarget.replacingOccurrences(of: "localhost", with: "127.0.0.1")
        let normLive = liveTarget.replacingOccurrences(of: "localhost", with: "127.0.0.1")
        return normRoute == normLive || normLive.contains(normRoute) || normRoute.contains(normLive)
    }
}
