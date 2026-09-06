import Foundation

/// Global path constants and resolution
public struct PathConstants {
    public static var baseDirectory: URL {
        if let customDir = ProcessInfo.processInfo.environment["TAIL_USERSPACE_DIR"], !customDir.isEmpty {
            return URL(fileURLWithPath: customDir)
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("TailUserspace", isDirectory: true)
    }

    public static var logsDirectory: URL {
        if let customDir = ProcessInfo.processInfo.environment["TAIL_USERSPACE_LOGS_DIR"], !customDir.isEmpty {
            return URL(fileURLWithPath: customDir)
        }
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        return library.appendingPathComponent("Logs", isDirectory: true).appendingPathComponent("TailUserspace", isDirectory: true)
    }

    public static var socketPath: String {
        baseDirectory.appendingPathComponent("tailscaled.sock").path
    }

    public static var statePath: String {
        baseDirectory.appendingPathComponent("tailscaled.state").path
    }

    public static var configPath: String {
        baseDirectory.appendingPathComponent("config.json").path
    }

    public static var configURL: URL {
        baseDirectory.appendingPathComponent("config.json")
    }

    public static var logFilePath: String {
        logsDirectory.appendingPathComponent("tailscaled.log").path
    }

    public static var logFileURL: URL {
        logsDirectory.appendingPathComponent("tailscaled.log")
    }

    public static var pidFilePath: String {
        baseDirectory.appendingPathComponent("tailscaled.pid").path
    }

    /// Ensures runtime storage and log directories exist
    public static func ensureDirectoriesExist() throws {
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
    }
}

/// Inbound Tailscale Serve Route (Local Port -> Tailnet HTTPS)
public struct ServeRoute: Codable, Identifiable, Equatable {
    public var id: String
    public var localPort: Int
    public var servePort: Int
    public var proto: String
    public var path: String
    public var enabled: Bool

    public init(id: String = UUID().uuidString, localPort: Int, servePort: Int = 443, proto: String = "https", path: String = "/", enabled: Bool = true) {
        self.id = id
        self.localPort = localPort
        self.servePort = servePort
        self.proto = proto
        self.path = path
        self.enabled = enabled
    }
}

/// Outbound Remote Proxy (Tailnet Host:Port -> Localhost Port)
public struct RemoteProxy: Codable, Identifiable, Equatable {
    public var id: String
    public var localPort: Int
    public var remoteHost: String
    public var remotePort: Int
    public var terminateTLS: Bool
    public var enabled: Bool

    public init(id: String = UUID().uuidString, localPort: Int, remoteHost: String, remotePort: Int, terminateTLS: Bool = false, enabled: Bool = true) {
        self.id = id
        self.localPort = localPort
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        self.terminateTLS = terminateTLS
        self.enabled = enabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.localPort = try container.decode(Int.self, forKey: .localPort)
        self.remoteHost = try container.decode(String.self, forKey: .remoteHost)
        self.remotePort = try container.decode(Int.self, forKey: .remotePort)
        self.terminateTLS = try container.decodeIfPresent(Bool.self, forKey: .terminateTLS) ?? false
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

/// Persistent user configuration
public struct TailUserspaceConfig: Codable, Equatable {
    public var autoStart: Bool
    public var socks5Port: Int
    public var httpProxyPort: Int
    public var serveRoutes: [ServeRoute]
    public var remoteProxies: [RemoteProxy]

    public init(
        autoStart: Bool = true,
        socks5Port: Int = 1055,
        httpProxyPort: Int = 1056,
        serveRoutes: [ServeRoute] = [],
        remoteProxies: [RemoteProxy] = []
    ) {
        self.autoStart = autoStart
        self.socks5Port = socks5Port
        self.httpProxyPort = httpProxyPort
        self.serveRoutes = serveRoutes
        self.remoteProxies = remoteProxies
    }

    public static let `default` = TailUserspaceConfig()
}

/// Live daemon and Tailscale connection status
public struct DaemonStatus: Codable {
    public var isProcessRunning: Bool
    public var pid: Int32?
    public var backendState: String // e.g. "Running", "NeedsLogin", "Stopped", "NoDaemon"
    public var selfName: String
    public var selfDNSName: String
    public var tailscaleIPs: [String]
    public var authURL: String?
    public var healthWarnings: [String]
    public var isOnline: Bool {
        backendState == "Running"
    }

    public init(
        isProcessRunning: Bool = false,
        pid: Int32? = nil,
        backendState: String = "NoDaemon",
        selfName: String = "",
        selfDNSName: String = "",
        tailscaleIPs: [String] = [],
        authURL: String? = nil,
        healthWarnings: [String] = []
    ) {
        self.isProcessRunning = isProcessRunning
        self.pid = pid
        self.backendState = backendState
        self.selfName = selfName
        self.selfDNSName = selfDNSName
        self.tailscaleIPs = tailscaleIPs
        self.authURL = authURL
        self.healthWarnings = healthWarnings
    }
}
