import Foundation

/// Defines all available MCP resources and handles resource reading
public struct MCPResources {

    public static let allResources: [MCPResource] = [
        MCPResource(
            uri: "tailuserspace://status",
            name: "TailUserspace Live Status",
            description: "Live status of the userspace tailscaled daemon process, Tailscale backend state, IPs, and MagicDNS domain",
            mimeType: "application/json"
        ),
        MCPResource(
            uri: "tailuserspace://config",
            name: "TailUserspace Configuration",
            description: "Current persistent JSON configuration (config.json) containing proxy ports, inbound serve routes, and outbound remote proxies",
            mimeType: "application/json"
        ),
        MCPResource(
            uri: "tailuserspace://serve",
            name: "Tailscale Inbound Serve Status",
            description: "Active inbound serve routes, ephemeral CLI sessions, and sync state against the live daemon",
            mimeType: "application/json"
        ),
        MCPResource(
            uri: "tailuserspace://proxies",
            name: "Outbound Remote Proxies Status",
            description: "List of configured outbound remote proxies with active listener states",
            mimeType: "application/json"
        ),
        MCPResource(
            uri: "tailuserspace://logs",
            name: "Tailscaled Daemon Logs",
            description: "Recent log lines from ~/Library/Logs/TailUserspace/tailscaled.log",
            mimeType: "text/plain"
        )
    ]

    /// Reads content of a resource by its URI
    public static func read(
        uri: String,
        client: TailscaleClient = .shared,
        supervisor: DaemonSupervisor = .shared,
        configManager: ConfigManager = .shared,
        forwarder: SOCKS5Forwarder = .shared
    ) throws -> (text: String, mimeType: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        switch uri {
        case "tailuserspace://status":
            let status = client.getStatus()
            let config = configManager.load()
            let (running, pid) = supervisor.isRunning()

            let obj: [String: Any] = [
                "isProcessRunning": running,
                "pid": pid as Any,
                "backendState": status.backendState,
                "isOnline": status.isOnline,
                "selfName": status.selfName,
                "selfDNSName": status.selfDNSName,
                "tailscaleIPs": status.tailscaleIPs,
                "authURL": status.authURL as Any,
                "healthWarnings": status.healthWarnings,
                "socks5Port": config.socks5Port,
                "httpProxyPort": config.httpProxyPort
            ]
            let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
            return (String(data: data, encoding: .utf8) ?? "{}", "application/json")

        case "tailuserspace://config":
            let config = configManager.load()
            let data = try encoder.encode(config)
            return (String(data: data, encoding: .utf8) ?? "{}", "application/json")

        case "tailuserspace://serve":
            let config = configManager.load()
            let discrepancies = client.checkServeDiscrepancies(config: config)
            let ephemeral = client.cleanupStaleEphemeralSessionsAndUnmount()

            var routesObj: [[String: Any]] = []
            for r in config.serveRoutes {
                let disc = discrepancies.first(where: { $0.route.id == r.id })
                routesObj.append([
                    "id": r.id,
                    "target": r.target,
                    "servePort": r.servePort,
                    "proto": r.proto,
                    "path": r.path,
                    "enabled": r.enabled,
                    "syncKind": disc?.kind.rawValue ?? "Unknown",
                    "liveTarget": disc?.liveTarget as Any
                ])
            }

            var ephemeralObj: [[String: Any]] = []
            for e in ephemeral {
                ephemeralObj.append([
                    "id": e.id,
                    "pid": e.pid,
                    "target": e.route.target,
                    "servePort": e.route.servePort,
                    "proto": e.route.proto,
                    "path": e.route.path
                ])
            }

            let resultObj: [String: Any] = [
                "routes": routesObj,
                "ephemeralSessions": ephemeralObj
            ]
            let data = try JSONSerialization.data(withJSONObject: resultObj, options: [.prettyPrinted, .sortedKeys])
            return (String(data: data, encoding: .utf8) ?? "{}", "application/json")

        case "tailuserspace://proxies":
            let config = configManager.load()
            var proxiesObj: [[String: Any]] = []
            for p in config.remoteProxies {
                let isRunning = forwarder.isProxyRunning(id: p.id)
                proxiesObj.append([
                    "id": p.id,
                    "localPort": p.localPort,
                    "remoteHost": p.remoteHost,
                    "remotePort": p.remotePort,
                    "terminateTLS": p.terminateTLS,
                    "enabled": p.enabled,
                    "isRunning": isRunning
                ])
            }
            let data = try JSONSerialization.data(withJSONObject: ["remoteProxies": proxiesObj], options: [.prettyPrinted, .sortedKeys])
            return (String(data: data, encoding: .utf8) ?? "{}", "application/json")

        case "tailuserspace://logs":
            let path = PathConstants.logFilePath
            guard FileManager.default.fileExists(atPath: path),
                  let content = try? String(contentsOfFile: path, encoding: .utf8) else {
                return ("No log file found at: \(path)", "text/plain")
            }
            let lines = content.components(separatedBy: .newlines)
            let tail = lines.suffix(100).joined(separator: "\n")
            return (tail, "text/plain")

        default:
            throw TailscaleClientError.jsonParsingFailed("Resource URI not found: '\(uri)'")
        }
    }
}
