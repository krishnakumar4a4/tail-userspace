import Foundation

public enum DaemonSupervisorError: LocalizedError {
    case tailscaledNotFound
    case daemonAlreadyRunning(pid: Int32)
    case failedToStart(String)
    case socketNotCreatedInTime

    public var errorDescription: String? {
        switch self {
        case .tailscaledNotFound:
            return "Could not find 'tailscaled' binary. Please ensure Tailscale is installed (e.g., via 'brew install tailscale')."
        case .daemonAlreadyRunning(let pid):
            return "Tailscale daemon is already running (PID: \(pid))."
        case .failedToStart(let reason):
            return "Failed to start tailscaled: \(reason)"
        case .socketNotCreatedInTime:
            return "Daemon started but unix socket was not created in time."
        }
    }
}

/// Supervises the lifecycle of the unprivileged userspace tailscaled process
public final class DaemonSupervisor {
    public static let shared = DaemonSupervisor()
    private var process: Process?

    public init() {}

    /// Locates the tailscaled executable
    public static func findTailscaledBinary() -> String? {
        if let custom = ProcessInfo.processInfo.environment["TAILSCALED_PATH"], FileManager.default.isExecutableFile(atPath: custom) {
            return custom
        }
        let candidates = [
            "/opt/homebrew/bin/tailscaled",
            "/usr/local/bin/tailscaled",
            "/usr/bin/tailscaled"
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        // Fallback to searching PATH via which
        let whichProcess = Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = ["tailscaled"]
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

    /// Checks if the daemon is currently running
    public func isRunning() -> (running: Bool, pid: Int32?) {
        guard let pid = readSavedPID() else {
            return (false, nil)
        }
        // kill with signal 0 checks if process exists and current user has permissions
        if kill(pid, 0) == 0 {
            return (true, pid)
        }
        // Process is dead, clean up stale PID file
        try? FileManager.default.removeItem(atPath: PathConstants.pidFilePath)
        return (false, nil)
    }

    /// Starts tailscaled with userspace networking arguments
    public func start(config: TailUserspaceConfig? = nil) throws -> Int32 {
        let (running, existingPID) = isRunning()
        if running, let pid = existingPID {
            return pid
        }

        guard let binaryPath = Self.findTailscaledBinary() else {
            throw DaemonSupervisorError.tailscaledNotFound
        }

        let cfg = config ?? ConfigManager.shared.load()
        try PathConstants.ensureDirectoriesExist()

        Logger.shared.info("Using tailscaled binary: \(binaryPath)")
        Logger.shared.debug("Socket path: \(PathConstants.socketPath)")
        Logger.shared.debug("State path:  \(PathConstants.statePath)")
        Logger.shared.debug("Logs path:   \(PathConstants.logFilePath)")

        // Clean up stale socket if daemon is not running
        if FileManager.default.fileExists(atPath: PathConstants.socketPath) {
            try? FileManager.default.removeItem(atPath: PathConstants.socketPath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = [
            "--tun=userspace-networking",
            "--socket=\(PathConstants.socketPath)",
            "--state=\(PathConstants.statePath)",
            "--statedir=\(PathConstants.baseDirectory.path)",
            "--socks5-server=localhost:\(cfg.socks5Port)",
            "--outbound-http-proxy-listen=localhost:\(cfg.httpProxyPort)"
        ]

        Logger.shared.debug("Arguments: \(process.arguments?.joined(separator: " ") ?? "")")

        // Redirect stdout/stderr to log file
        let logURL = URL(fileURLWithPath: PathConstants.logFilePath)
        if !FileManager.default.fileExists(atPath: PathConstants.logFilePath) {
            FileManager.default.createFile(atPath: PathConstants.logFilePath, contents: nil)
        }
        let fileHandle = try FileHandle(forWritingTo: logURL)
        fileHandle.seekToEndOfFile()
        process.standardOutput = fileHandle
        process.standardError = fileHandle

        do {
            try process.run()
        } catch {
            throw DaemonSupervisorError.failedToStart(error.localizedDescription)
        }

        let pid = process.processIdentifier
        try "\(pid)".write(toFile: PathConstants.pidFilePath, atomically: true, encoding: .utf8)
        self.process = process
        Logger.shared.info("Daemon process spawned (PID: \(pid)). Awaiting unix socket...")

        // Wait up to 4 seconds for socket to be ready
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < 4.0 {
            if FileManager.default.fileExists(atPath: PathConstants.socketPath) {
                Logger.shared.debug("Socket detected and ready at \(PathConstants.socketPath)")
                return pid
            }
            usleep(100_000) // 100ms
        }

        // Even if socket took slightly longer, process is running
        return pid
    }

    /// Gracefully stops tailscaled
    public func stop() throws {
        let (running, pid) = isRunning()
        guard running, let targetPID = pid else {
            // Clean up files just in case
            try? FileManager.default.removeItem(atPath: PathConstants.pidFilePath)
            try? FileManager.default.removeItem(atPath: PathConstants.socketPath)
            return
        }

        Logger.shared.info("Sending SIGTERM to daemon process (PID: \(targetPID))...")
        // Send SIGTERM
        kill(targetPID, SIGTERM)

        // Wait up to 5 seconds for process to exit
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < 5.0 {
            if kill(targetPID, 0) != 0 {
                // Terminated successfully
                break
            }
            usleep(200_000) // 200ms
        }

        // If still alive, force kill with SIGKILL
        if kill(targetPID, 0) == 0 {
            kill(targetPID, SIGKILL)
        }

        try? FileManager.default.removeItem(atPath: PathConstants.pidFilePath)
        try? FileManager.default.removeItem(atPath: PathConstants.socketPath)
        self.process = nil
    }

    private func readSavedPID() -> Int32? {
        guard let content = try? String(contentsOfFile: PathConstants.pidFilePath, encoding: .utf8) else {
            return nil
        }
        return Int32(content.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
