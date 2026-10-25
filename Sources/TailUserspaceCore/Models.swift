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

    public static var ephemeralSessionsPath: String {
        baseDirectory.appendingPathComponent("ephemeral_sessions.json").path
    }

    public static var ephemeralSessionsURL: URL {
        baseDirectory.appendingPathComponent("ephemeral_sessions.json")
    }

    /// Ensures runtime storage and log directories exist
    public static func ensureDirectoriesExist() throws {
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
    }
}

/// Inbound Tailscale Serve Route (Local Port/URL/Socket -> Tailnet)
public struct ServeRoute: Codable, Identifiable, Equatable {
    public var id: String
    public var target: String
    public var servePort: Int
    public var proto: String
    public var path: String
    public var enabled: Bool
    public var proxyProtocol: Int?
    public var isEphemeral: Bool
    public var ephemeralPID: Int32?

    /// Backward-compatible localPort computed property
    public var localPort: Int {
        if let p = Int(target) { return p }
        if let url = URL(string: target), let p = url.port { return p }
        let parts = target.split(separator: ":")
        if parts.count >= 2, let p = Int(parts.last?.split(separator: "/").first ?? "") {
            return p
        }
        return 0
    }

    public init(
        id: String = UUID().uuidString,
        target: String,
        servePort: Int = 443,
        proto: String = "https",
        path: String = "/",
        enabled: Bool = true,
        proxyProtocol: Int? = nil,
        isEphemeral: Bool = false,
        ephemeralPID: Int32? = nil
    ) {
        self.id = id
        self.target = target
        self.servePort = servePort
        self.proto = proto
        self.path = path.hasPrefix("/") ? path : "/\(path)"
        self.enabled = enabled
        self.proxyProtocol = proxyProtocol
        self.isEphemeral = isEphemeral
        self.ephemeralPID = ephemeralPID
    }

    /// Convenience initializer preserving legacy (localPort: Int) call sites
    public init(
        id: String = UUID().uuidString,
        localPort: Int,
        servePort: Int = 443,
        proto: String = "https",
        path: String = "/",
        enabled: Bool = true,
        proxyProtocol: Int? = nil,
        isEphemeral: Bool = false,
        ephemeralPID: Int32? = nil
    ) {
        self.id = id
        self.target = "\(localPort)"
        self.servePort = servePort
        self.proto = proto
        self.path = path.hasPrefix("/") ? path : "/\(path)"
        self.enabled = enabled
        self.proxyProtocol = proxyProtocol
        self.isEphemeral = isEphemeral
        self.ephemeralPID = ephemeralPID
    }

    enum CodingKeys: String, CodingKey {
        case id, target, localPort, servePort, proto, path, enabled, proxyProtocol, isEphemeral, ephemeralPID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        if let rawTarget = try container.decodeIfPresent(String.self, forKey: .target) {
            self.target = rawTarget
        } else if let legacyPort = try container.decodeIfPresent(Int.self, forKey: .localPort) {
            self.target = "\(legacyPort)"
        } else {
            self.target = "0"
        }
        self.servePort = try container.decodeIfPresent(Int.self, forKey: .servePort) ?? 443
        self.proto = try container.decodeIfPresent(String.self, forKey: .proto) ?? "https"
        let rawPath = try container.decodeIfPresent(String.self, forKey: .path) ?? "/"
        self.path = rawPath.hasPrefix("/") ? rawPath : "/\(rawPath)"
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        self.proxyProtocol = try container.decodeIfPresent(Int.self, forKey: .proxyProtocol)
        self.isEphemeral = try container.decodeIfPresent(Bool.self, forKey: .isEphemeral) ?? false
        self.ephemeralPID = try container.decodeIfPresent(Int32.self, forKey: .ephemeralPID)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(target, forKey: .target)
        try container.encode(localPort, forKey: .localPort)
        try container.encode(servePort, forKey: .servePort)
        try container.encode(proto, forKey: .proto)
        try container.encode(path, forKey: .path)
        try container.encode(enabled, forKey: .enabled)
        try container.encodeIfPresent(proxyProtocol, forKey: .proxyProtocol)
        try container.encode(isEphemeral, forKey: .isEphemeral)
        try container.encodeIfPresent(ephemeralPID, forKey: .ephemeralPID)
    }
}

/// An ephemeral serve session managed by a foreground CLI process
public struct EphemeralServeSession: Codable, Identifiable, Equatable {
    public var id: String
    public var pid: Int32
    public var route: ServeRoute
    public var createdAt: Date

    public init(id: String = UUID().uuidString, pid: Int32, route: ServeRoute, createdAt: Date = Date()) {
        self.id = id
        self.pid = pid
        self.route = route
        self.createdAt = createdAt
    }
}

/// Discrepancy between persistent configuration and live daemon serve state
public enum DiscrepancyKind: String, Codable {
    case inSync = "In Sync"
    case notOnDaemon = "In Config, Not Active on Daemon"
    case daemonOnly = "Active on Daemon, Not in Config"
    case cliEphemeral = "CLI Ephemeral Session"
    case mismatch = "Configuration Mismatch"
}

public struct ServeDiscrepancy: Equatable {
    public var kind: DiscrepancyKind
    public var route: ServeRoute
    public var liveTarget: String?
    public var message: String

    public init(kind: DiscrepancyKind, route: ServeRoute, liveTarget: String? = nil, message: String) {
        self.kind = kind
        self.route = route
        self.liveTarget = liveTarget
        self.message = message
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
    public var mcpPort: Int
    public var mcpEnabled: Bool
    public var serveRoutes: [ServeRoute]
    public var remoteProxies: [RemoteProxy]

    public init(
        autoStart: Bool = true,
        socks5Port: Int = 1055,
        httpProxyPort: Int = 1056,
        mcpPort: Int = 1058,
        mcpEnabled: Bool = true,
        serveRoutes: [ServeRoute] = [],
        remoteProxies: [RemoteProxy] = []
    ) {
        self.autoStart = autoStart
        self.socks5Port = socks5Port
        self.httpProxyPort = httpProxyPort
        self.mcpPort = mcpPort
        self.mcpEnabled = mcpEnabled
        self.serveRoutes = serveRoutes
        self.remoteProxies = remoteProxies
    }

    public static let `default` = TailUserspaceConfig()

    enum CodingKeys: String, CodingKey {
        case autoStart, socks5Port, httpProxyPort, mcpPort, mcpEnabled, serveRoutes, remoteProxies
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.autoStart = try container.decodeIfPresent(Bool.self, forKey: .autoStart) ?? true
        self.socks5Port = try container.decodeIfPresent(Int.self, forKey: .socks5Port) ?? 1055
        self.httpProxyPort = try container.decodeIfPresent(Int.self, forKey: .httpProxyPort) ?? 1056
        self.mcpPort = try container.decodeIfPresent(Int.self, forKey: .mcpPort) ?? 1058
        self.mcpEnabled = try container.decodeIfPresent(Bool.self, forKey: .mcpEnabled) ?? true
        self.serveRoutes = try container.decodeIfPresent([ServeRoute].self, forKey: .serveRoutes) ?? []
        self.remoteProxies = try container.decodeIfPresent([RemoteProxy].self, forKey: .remoteProxies) ?? []
    }
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
