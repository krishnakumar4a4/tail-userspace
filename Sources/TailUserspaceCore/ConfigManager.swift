import Foundation

/// Manages loading, mutating, and persisting user configuration
public final class ConfigManager {
    public static let shared = ConfigManager()
    private let lock = NSLock()
    private var cachedConfig: TailUserspaceConfig?

    public init() {}

    /// Loads the persisted configuration from disk or returns default
    public func load() -> TailUserspaceConfig {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cachedConfig {
            return cached
        }

        let path = PathConstants.configPath
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let config = try? JSONDecoder().decode(TailUserspaceConfig.self, from: data) else {
            let def = TailUserspaceConfig.default
            cachedConfig = def
            return def
        }

        cachedConfig = config
        return config
    }

    /// Persists configuration to disk atomically
    public func save(_ config: TailUserspaceConfig) throws {
        lock.lock()
        defer { lock.unlock() }

        try PathConstants.ensureDirectoriesExist()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)

        let fileURL = URL(fileURLWithPath: PathConstants.configPath)
        try data.write(to: fileURL, options: .atomic)
        cachedConfig = config
    }

    // MARK: - Inbound Serve Route Mutation

    public func addServeRoute(_ route: ServeRoute) throws {
        var config = load()
        // Replace existing route for same local port if present
        config.serveRoutes.removeAll { $0.localPort == route.localPort || $0.id == route.id }
        config.serveRoutes.append(route)
        try save(config)
    }

    public func removeServeRoute(id: String) throws {
        var config = load()
        config.serveRoutes.removeAll { $0.id == id }
        try save(config)
    }

    public func toggleServeRoute(id: String) throws {
        var config = load()
        if let idx = config.serveRoutes.firstIndex(where: { $0.id == id }) {
            config.serveRoutes[idx].enabled.toggle()
            try save(config)
        }
    }

    // MARK: - Outbound Remote Proxy Mutation

    public func addRemoteProxy(_ proxy: RemoteProxy) throws {
        var config = load()
        // Replace existing proxy for same local port if present
        config.remoteProxies.removeAll { $0.localPort == proxy.localPort || $0.id == proxy.id }
        config.remoteProxies.append(proxy)
        try save(config)
    }

    public func removeRemoteProxy(id: String) throws {
        var config = load()
        config.remoteProxies.removeAll { $0.id == id }
        try save(config)
    }

    public func toggleRemoteProxy(id: String) throws {
        var config = load()
        if let idx = config.remoteProxies.firstIndex(where: { $0.id == id }) {
            config.remoteProxies[idx].enabled.toggle()
            try save(config)
        }
    }
}
