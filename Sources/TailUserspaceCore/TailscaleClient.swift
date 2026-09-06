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

    /// Applies an Inbound Serve route: exposes a local port to the tailnet
    public func applyServeRoute(_ route: ServeRoute) throws {
        // e.g. tailscale serve --bg --https=443 3000
        var args = ["serve", "--bg"]
        if route.proto == "https" {
            args.append("--https=\(route.servePort)")
        } else if route.proto == "http" {
            args.append("--http=\(route.servePort)")
        } else if route.proto == "tcp" {
            args.append("--tcp=\(route.servePort)")
        }
        if route.path != "/" && !route.path.isEmpty {
            args.append("--set-path=\(route.path)")
        }
        args.append("\(route.localPort)")

        try runCommand(args)
    }

    /// Resets all Tailscale Serve configurations on the node
    public func resetServe() throws {
        try runCommand(["serve", "reset"])
    }

    /// Reads and applies all enabled serve routes from the config
    public func reapplyConfiguredServeRoutes(_ config: TailUserspaceConfig) throws {
        // Only reapply if online
        let status = getStatus()
        guard status.isOnline else { return }

        for route in config.serveRoutes where route.enabled {
            try? applyServeRoute(route)
        }
    }

    /// Returns human-readable serve status
    public func getServeStatus() -> String {
        (try? runCommand(["serve", "status"])) ?? "No active serve endpoints"
    }
}
