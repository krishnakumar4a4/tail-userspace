import Foundation

/// Manages loading, mutating, and persisting user configuration
public final class ConfigManager {
    public static let shared = ConfigManager()
    private let lock = NSLock()
    private var cachedConfig: TailUserspaceConfig?
    private var lastModifiedDate: Date?

    public init() {}

    /// Loads the persisted configuration from disk, automatically reloading if file changed on disk
    public func load(forceReload: Bool = false) -> TailUserspaceConfig {
        lock.lock()
        defer { lock.unlock() }

        let path = PathConstants.configPath
        let currentModDate = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]) as? Date

        if !forceReload, let cached = cachedConfig, currentModDate != nil && currentModDate == lastModifiedDate {
            return cached
        }

        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let config = try? JSONDecoder().decode(TailUserspaceConfig.self, from: data) else {
            let def = TailUserspaceConfig.default
            cachedConfig = def
            lastModifiedDate = currentModDate
            return def
        }

        cachedConfig = config
        lastModifiedDate = currentModDate
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
        lastModifiedDate = (try? FileManager.default.attributesOfItem(atPath: PathConstants.configPath)[.modificationDate]) as? Date
    }

    // MARK: - Inbound Serve Route Mutation

    public func addServeRoute(_ route: ServeRoute) throws {
        var config = load()
        // Replace existing route for same local port if present
        config.serveRoutes.removeAll { $0.localPort == route.localPort || $0.id == route.id }
        config.serveRoutes.append(route)
        try save(config)
    }

    public func updateServeRoute(id: String, updatedRoute: ServeRoute) throws {
        var config = load()
        if config.serveRoutes.contains(where: { $0.id == id }) {
            // Remove any other route that might conflict with the new localPort
            config.serveRoutes.removeAll { $0.id != id && $0.localPort == updatedRoute.localPort }
            if let newIdx = config.serveRoutes.firstIndex(where: { $0.id == id }) {
                config.serveRoutes[newIdx] = updatedRoute
            } else {
                config.serveRoutes.append(updatedRoute)
            }
            try save(config)
        }
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

    public func updateRemoteProxy(id: String, updatedProxy: RemoteProxy) throws {
        var config = load()
        if config.remoteProxies.contains(where: { $0.id == id }) {
            // Remove any other proxy that might conflict with the new localPort
            config.remoteProxies.removeAll { $0.id != id && $0.localPort == updatedProxy.localPort }
            if let newIdx = config.remoteProxies.firstIndex(where: { $0.id == id }) {
                config.remoteProxies[newIdx] = updatedProxy
            } else {
                config.remoteProxies.append(updatedProxy)
            }
            try save(config)
        }
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
