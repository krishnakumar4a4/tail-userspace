import Foundation

/// Defines all available MCP tools and handles their execution
public struct MCPTools {

    public static let allTools: [MCPTool] = [
        MCPTool(
            name: "get_status",
            description: "Get real-time TailUserspace daemon process status, Tailscale network backend state, node IP addresses, MagicDNS domain name, auth URLs, and health warnings.",
            inputSchema: [
                "type": "object",
                "properties": [:] as [String: Any],
                "required": [] as [String]
            ]
        ),
        MCPTool(
            name: "daemon_start",
            description: "Start the unprivileged userspace tailscaled daemon, initialize configured SOCKS5 proxy listeners, and reapply active inbound serve routes.",
            inputSchema: [
                "type": "object",
                "properties": [:] as [String: Any],
                "required": [] as [String]
            ]
        ),
        MCPTool(
            name: "daemon_stop",
            description: "Stop the unprivileged userspace tailscaled daemon and all active outbound proxy forwarders.",
            inputSchema: [
                "type": "object",
                "properties": [:] as [String: Any],
                "required": [] as [String]
            ]
        ),
        MCPTool(
            name: "connect",
            description: "Connect the node to the Tailscale network ('tailscale up'). If web authorization is required, returns the authentication URL.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "extraArgs": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "Optional additional CLI arguments to pass to 'tailscale up' (e.g. ['--accept-routes', '--advertise-tags=...'])."
                    ],
                    "timeout": [
                        "type": "number",
                        "description": "Connection timeout in seconds (default: 30)."
                    ],
                    "openBrowser": [
                        "type": "boolean",
                        "description": "Whether to automatically open the default macOS browser if an authentication URL is needed (default: true)."
                    ]
                ],
                "required": [] as [String]
            ]
        ),
        MCPTool(
            name: "disconnect",
            description: "Disconnect the node from the Tailscale network ('tailscale down').",
            inputSchema: [
                "type": "object",
                "properties": [:] as [String: Any],
                "required": [] as [String]
            ]
        ),
        MCPTool(
            name: "get_env",
            description: "Get shell environment proxy variables (ALL_PROXY, HTTP_PROXY, HTTPS_PROXY) and ports for routing command line or app traffic through the userspace Tailscale proxy.",
            inputSchema: [
                "type": "object",
                "properties": [:] as [String: Any],
                "required": [] as [String]
            ]
        ),
        MCPTool(
            name: "get_daemon_logs",
            description: "Read recent lines from the userspace tailscaled daemon log file (tailscaled.log).",
            inputSchema: [
                "type": "object",
                "properties": [
                    "lines": [
                        "type": "integer",
                        "description": "Number of lines from the end of the log to return (default: 50, max: 500)."
                    ]
                ],
                "required": [] as [String]
            ]
        ),
        MCPTool(
            name: "list_serve_routes",
            description: "List all configured inbound serve routes (exposing local services to the tailnet via HTTPS/TCP) with live sync state and active CLI ephemeral sessions.",
            inputSchema: [
                "type": "object",
                "properties": [:] as [String: Any],
                "required": [] as [String]
            ]
        ),
        MCPTool(
            name: "add_serve_route",
            description: "Expose a local port, URL, or service to your tailnet via Tailscale Serve. Automatically manages HTTPS certificates with MagicDNS.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "target": [
                        "type": "string",
                        "description": "Local service target. Examples: '3000', 'http://localhost:3000/api', or 'https+insecure://localhost:8443'."
                    ],
                    "servePort": [
                        "type": "integer",
                        "description": "Tailnet port to expose (default: 443 for HTTPS, 80 for HTTP)."
                    ],
                    "proto": [
                        "type": "string",
                        "enum": ["https", "http", "tcp", "tls-terminated-tcp"],
                        "description": "Protocol to serve on the tailnet (default: 'https')."
                    ],
                    "path": [
                        "type": "string",
                        "description": "Subpath mount for HTTP/HTTPS handlers (default: '/')."
                    ],
                    "proxyProtocol": [
                        "type": "integer",
                        "enum": [1, 2],
                        "description": "Optional PROXY protocol header version (1 or 2) to send to upstream."
                    ],
                    "background": [
                        "type": "boolean",
                        "description": "Whether to save route permanently to config.json and mount in background (default: true)."
                    ]
                ],
                "required": ["target"]
            ]
        ),
        MCPTool(
            name: "remove_serve_route",
            description: "Remove an inbound serve route from configuration and unmount it from the live daemon.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": [
                        "type": "string",
                        "description": "UUID of the serve route to remove."
                    ],
                    "target": [
                        "type": "string",
                        "description": "Target port or URL to match if ID is not known."
                    ],
                    "servePort": [
                        "type": "integer",
                        "description": "Tailnet serve port (default: 443)."
                    ],
                    "path": [
                        "type": "string",
                        "description": "Mount path (default: '/')."
                    ],
                    "proto": [
                        "type": "string",
                        "enum": ["https", "http", "tcp", "tls-terminated-tcp"],
                        "description": "Protocol of the route to remove (default: 'https')."
                    ]
                ],
                "required": [] as [String]
            ]
        ),
        MCPTool(
            name: "reapply_serve_routes",
            description: "Synchronize and reapply all enabled serve routes from config.json to the running Tailscale daemon.",
            inputSchema: [
                "type": "object",
                "properties": [:] as [String: Any],
                "required": [] as [String]
            ]
        ),
        MCPTool(
            name: "reset_serve",
            description: "Reset and clear all active Tailscale Serve endpoints on the running daemon.",
            inputSchema: [
                "type": "object",
                "properties": [:] as [String: Any],
                "required": [] as [String]
            ]
        ),
        MCPTool(
            name: "get_serve_status",
            description: "Get raw text or parsed JSON output of 'tailscale serve status' from the live daemon.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "json": [
                        "type": "boolean",
                        "description": "Return output in JSON format if true (default: false)."
                    ]
                ],
                "required": [] as [String]
            ]
        ),
        MCPTool(
            name: "list_remote_proxies",
            description: "List all configured outbound remote proxies (tunneling local ports to remote tailnet services) and check active listener status.",
            inputSchema: [
                "type": "object",
                "properties": [:] as [String: Any],
                "required": [] as [String]
            ]
        ),
        MCPTool(
            name: "add_remote_proxy",
            description: "Forward a local port on your Mac to a remote tailnet service (e.g. localhost:8080 -> nas.ts.net:80) via SOCKS5 forwarder.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "localPort": [
                        "type": "integer",
                        "description": "Local port on your Mac to listen on (e.g. 8080)."
                    ],
                    "remoteHost": [
                        "type": "string",
                        "description": "Destination hostname or IP on the tailnet (e.g. 'nas.ts.net' or '100.64.0.10')."
                    ],
                    "remotePort": [
                        "type": "integer",
                        "description": "Destination port on the remote tailnet host (default: 80)."
                    ],
                    "terminateTLS": [
                        "type": "boolean",
                        "description": "If true, terminates remote TLS and presents plain HTTP locally, eliminating SSL certificate/SNI validation errors (default: false)."
                    ]
                ],
                "required": ["localPort", "remoteHost"]
            ]
        ),
        MCPTool(
            name: "remove_remote_proxy",
            description: "Remove an outbound remote proxy by local port or proxy ID, stopping its local TCP listener.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "localPort": [
                        "type": "integer",
                        "description": "Local port of the proxy to remove."
                    ],
                    "id": [
                        "type": "string",
                        "description": "UUID of the proxy to remove."
                    ]
                ],
                "required": [] as [String]
            ]
        ),
        MCPTool(
            name: "toggle_remote_proxy",
            description: "Enable or disable an outbound remote proxy without deleting its configuration.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "localPort": [
                        "type": "integer",
                        "description": "Local port of the proxy to toggle."
                    ],
                    "id": [
                        "type": "string",
                        "description": "UUID of the proxy to toggle."
                    ]
                ],
                "required": [] as [String]
            ]
        ),
        MCPTool(
            name: "get_config",
            description: "Read the current persistent configuration (config.json) including SOCKS5/HTTP proxy ports, autoStart setting, serve routes, and remote proxies.",
            inputSchema: [
                "type": "object",
                "properties": [:] as [String: Any],
                "required": [] as [String]
            ]
        ),
        MCPTool(
            name: "update_config",
            description: "Update persistent settings such as proxy ports (socks5Port, httpProxyPort) or autoStart.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "socks5Port": [
                        "type": "integer",
                        "description": "Port for local SOCKS5 proxy (default: 1055)."
                    ],
                    "httpProxyPort": [
                        "type": "integer",
                        "description": "Port for local outbound HTTP proxy (default: 1056)."
                    ],
                    "autoStart": [
                        "type": "boolean",
                        "description": "Whether to auto-start daemon on app launch."
                    ],
                    "mcpPort": [
                        "type": "integer",
                        "description": "Port for local HTTP MCP server (default: 1058)."
                    ],
                    "mcpEnabled": [
                        "type": "boolean",
                        "description": "Whether the embedded HTTP MCP server is enabled (default: true)."
                    ]
                ],
                "required": [] as [String]
            ]
        )
    ]

    /// Executes the specified tool with arguments and returns formatted string output
    public static func execute(
        name: String,
        arguments: [String: Any],
        client: TailscaleClient = .shared,
        supervisor: DaemonSupervisor = .shared,
        configManager: ConfigManager = .shared,
        forwarder: SOCKS5Forwarder = .shared
    ) throws -> String {
        switch name {
        case "get_status":
            let status = client.getStatus()
            let config = configManager.load()
            let discrepancies = client.checkServeDiscrepancies(config: config)
            let activeEphemeral = client.cleanupStaleEphemeralSessionsAndUnmount()

            var dict: [String: Any] = [
                "isProcessRunning": status.isProcessRunning,
                "pid": status.pid as Any,
                "backendState": status.backendState,
                "isOnline": status.isOnline,
                "selfName": status.selfName,
                "selfDNSName": status.selfDNSName,
                "tailscaleIPs": status.tailscaleIPs,
                "healthWarnings": status.healthWarnings,
                "socks5Proxy": "127.0.0.1:\(config.socks5Port)",
                "httpProxy": "127.0.0.1:\(config.httpProxyPort)",
                "mcpServer": "http://127.0.0.1:\(config.mcpPort)/mcp",
                "mcpPort": config.mcpPort,
                "mcpEnabled": config.mcpEnabled,
                "configuredServeRoutesCount": config.serveRoutes.count,
                "configuredRemoteProxiesCount": config.remoteProxies.count,
                "activeEphemeralServeSessionsCount": activeEphemeral.count
            ]
            if let authURL = status.authURL {
                dict["authURL"] = authURL
            }

            var textLines: [String] = []
            textLines.append("=== Tailscale Userspace Daemon Status ===")
            if status.isProcessRunning, let pid = status.pid {
                textLines.append("● Process:       Running (PID: \(pid))")
            } else {
                textLines.append("○ Process:       Stopped")
            }
            textLines.append("  Backend State: \(status.backendState)")
            if !status.selfName.isEmpty {
                textLines.append("  Node Name:     \(status.selfName)")
            }
            if !status.selfDNSName.isEmpty {
                textLines.append("  Tailnet DNS:   \(status.selfDNSName)")
            }
            if !status.tailscaleIPs.isEmpty {
                textLines.append("  Tailscale IPs: \(status.tailscaleIPs.joined(separator: ", "))")
            }
            if let authURL = status.authURL, !authURL.isEmpty {
                textLines.append("  Auth URL:      \(authURL)")
            }
            textLines.append("  SOCKS5 Proxy:  127.0.0.1:\(config.socks5Port)")
            textLines.append("  HTTP Proxy:    127.0.0.1:\(config.httpProxyPort)")
            textLines.append("  MCP Server:    http://127.0.0.1:\(config.mcpPort)/mcp (\(config.mcpEnabled ? "Enabled" : "Disabled"))")

            let errors = discrepancies.filter { $0.kind == .notOnDaemon || $0.kind == .mismatch }
            if !errors.isEmpty {
                textLines.append("\n⚠️ Route Discrepancies:")
                for e in errors {
                    textLines.append("  • \(e.message)")
                }
            }

            let jsonData = (try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])) ?? Data()
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
            return textLines.joined(separator: "\n") + "\n\nJSON:\n" + jsonString

        case "daemon_start":
            let config = configManager.load()
            let (running, existingPID) = supervisor.isRunning()
            if running, let pid = existingPID {
                return "Tailscale userspace daemon is already running (PID: \(pid))."
            }
            let pid = try supervisor.start(config: config)
            forwarder.startConfiguredProxies(config)
            try? client.reapplyConfiguredServeRoutes(config)
            return "✓ Tailscale userspace daemon started successfully (PID: \(pid)).\n  SOCKS5: 127.0.0.1:\(config.socks5Port)\n  HTTP Proxy: 127.0.0.1:\(config.httpProxyPort)"

        case "daemon_stop":
            forwarder.stopAll()
            try supervisor.stop()
            return "✓ Tailscale userspace daemon and proxy listeners stopped."

        case "connect":
            let extraArgs = arguments["extraArgs"] as? [String] ?? []
            let timeout = arguments["timeout"] as? Double ?? 30.0
            let openBrowser = arguments["openBrowser"] as? Bool ?? true

            var detectedAuthURL: String? = nil
            do {
                try client.connect(
                    extraArgs: extraArgs,
                    timeout: timeout,
                    autoOpenBrowser: openBrowser,
                    onAuthURL: { url in
                        detectedAuthURL = url.absoluteString
                    }
                )
                let st = client.getStatus()
                return "✓ Connected to Tailscale network!\n  Node DNS: \(st.selfDNSName)\n  IPs: \(st.tailscaleIPs.joined(separator: ", "))"
            } catch {
                if let auth = detectedAuthURL ?? client.getStatus().authURL {
                    return "Authentication Required. Please complete login in your browser:\n👉 \(auth)"
                }
                throw error
            }

        case "disconnect":
            try client.disconnect()
            return "✓ Disconnected from Tailscale network."

        case "get_env":
            let config = configManager.load()
            let envScript = """
            export ALL_PROXY=socks5://127.0.0.1:\(config.socks5Port)
            export HTTP_PROXY=http://127.0.0.1:\(config.httpProxyPort)
            export HTTPS_PROXY=http://127.0.0.1:\(config.httpProxyPort)
            export all_proxy=socks5://127.0.0.1:\(config.socks5Port)
            export http_proxy=http://127.0.0.1:\(config.httpProxyPort)
            export https_proxy=http://127.0.0.1:\(config.httpProxyPort)
            """
            return envScript

        case "get_daemon_logs":
            let maxLines = min(max(arguments["lines"] as? Int ?? 50, 1), 500)
            let path = PathConstants.logFilePath
            guard FileManager.default.fileExists(atPath: path),
                  let content = try? String(contentsOfFile: path, encoding: .utf8) else {
                return "No log file found at: \(path)"
            }
            let lines = content.components(separatedBy: .newlines)
            let tail = lines.suffix(maxLines).joined(separator: "\n")
            return "=== Last \(min(lines.count, maxLines)) lines of \(path) ===\n" + tail

        case "list_serve_routes":
            let config = configManager.load()
            let status = client.getStatus()
            let host = status.selfDNSName.isEmpty ? "your-node.ts.net" : status.selfDNSName
            let discrepancies = client.checkServeDiscrepancies(config: config)
            let activeEphemeral = client.cleanupStaleEphemeralSessionsAndUnmount()

            if config.serveRoutes.isEmpty && activeEphemeral.isEmpty {
                return "No inbound serve routes configured."
            }

            var lines: [String] = ["=== Inbound Serve Routes (Local ➔ Tailnet) ==="]
            for r in config.serveRoutes {
                let d = discrepancies.first(where: { $0.route.id == r.id })
                let badge: String
                switch d?.kind {
                case .inSync: badge = "[✓ In Sync]"
                case .notOnDaemon: badge = "[⚠️ Offline/Not on Daemon]"
                case .mismatch: badge = "[🔄 Mismatch: \(d?.liveTarget ?? "")]"
                default: badge = r.enabled ? "[Active]" : "[Disabled]"
                }
                lines.append("• ID: \(r.id)")
                lines.append("  \(badge) \(r.target) ➔ \(r.proto)://\(host):\(r.servePort)\(r.path)")
            }

            for eph in activeEphemeral {
                lines.append("• [⚡ CLI Ephemeral] (PID: \(eph.pid)) \(eph.route.target) ➔ \(eph.route.proto)://\(host):\(eph.route.servePort)\(eph.route.path)")
            }

            return lines.joined(separator: "\n")

        case "add_serve_route":
            guard let rawTarget = arguments["target"] as? String, !rawTarget.isEmpty else {
                throw TailscaleClientError.jsonParsingFailed("Missing required argument 'target'")
            }

            var normalizedTarget = rawTarget
            if normalizedTarget.hasPrefix("localhost:") || normalizedTarget.hasPrefix("127.0.0.1:") {
                normalizedTarget = "http://" + normalizedTarget
            }

            let servePort = arguments["servePort"] as? Int ?? 443
            let proto = arguments["proto"] as? String ?? "https"
            var path = arguments["path"] as? String ?? "/"
            if !path.hasPrefix("/") {
                path = "/" + path
            }
            let proxyProtocol = arguments["proxyProtocol"] as? Int
            let background = arguments["background"] as? Bool ?? true

            let route = ServeRoute(
                target: normalizedTarget,
                servePort: servePort,
                proto: proto,
                path: path,
                enabled: true,
                proxyProtocol: proxyProtocol
            )

            if background {
                try configManager.addServeRoute(route)
            }

            let status = client.getStatus()
            let host = status.selfDNSName.isEmpty ? "your-node.ts.net" : status.selfDNSName

            var resultMsg = "✓ Serve route created (ID: \(route.id)):\n"
            resultMsg += "  Local Target: \(route.target)\n"
            resultMsg += "  Tailnet URL:  \(route.proto)://\(host):\(route.servePort)\(route.path)"

            if status.isOnline {
                try client.applyServeRoute(route, background: true)
                resultMsg += "\n  Status:       Active and mounted on live Tailscale daemon."
            } else {
                resultMsg += "\n  Status:       Saved to config.json. Will activate when daemon starts."
            }
            return resultMsg

        case "remove_serve_route":
            let config = configManager.load()
            let target = arguments["target"] as? String
            let id = arguments["id"] as? String
            let servePort = arguments["servePort"] as? Int ?? 443
            let path = arguments["path"] as? String ?? "/"
            let proto = arguments["proto"] as? String ?? "https"

            var routeToRemove: ServeRoute? = nil
            if let id = id {
                routeToRemove = config.serveRoutes.first(where: { $0.id == id })
            } else if let target = target {
                routeToRemove = config.serveRoutes.first(where: {
                    $0.target == target ||
                    "\($0.localPort)" == target ||
                    $0.target.contains(":\(target)")
                })
            } else {
                routeToRemove = config.serveRoutes.first(where: {
                    $0.servePort == servePort && $0.path == path && $0.proto == proto
                })
            }

            if let r = routeToRemove {
                try? client.removeServeRouteLive(r)
                try configManager.removeServeRoute(id: r.id)
                return "✓ Removed serve route (ID: \(r.id)): \(r.target) (\(r.proto)://:\(r.servePort)\(r.path))"
            } else {
                let unmanaged = ServeRoute(target: target ?? "", servePort: servePort, proto: proto, path: path)
                try? client.removeServeRouteLive(unmanaged)
                return "✓ Unmounted serve endpoint \(proto)://:\(servePort)\(path) on live daemon."
            }

        case "reapply_serve_routes":
            let config = configManager.load()
            let status = client.getStatus()
            guard status.isOnline else {
                return "Cannot reapply routes: Tailscale daemon is currently offline."
            }
            try client.reapplyConfiguredServeRoutes(config)
            let count = config.serveRoutes.filter { $0.enabled }.count
            return "✓ Reapplied \(count) serve route(s) to live daemon."

        case "reset_serve":
            try client.resetServe()
            return "✓ Tailscale serve reset on live daemon."

        case "get_serve_status":
            let json = arguments["json"] as? Bool ?? false
            return client.getServeStatus(json: json)

        case "list_remote_proxies":
            let config = configManager.load()
            if config.remoteProxies.isEmpty {
                return "No outbound remote proxies configured."
            }

            var lines: [String] = ["=== Outbound Remote Proxies (Local ➔ Tailnet) ==="]
            for p in config.remoteProxies {
                let isRunning = forwarder.isProxyRunning(id: p.id)
                let statusBadge = isRunning ? "[● Running]" : (p.enabled ? "[○ Enabled/Idle]" : "[Disabled]")
                let tlsBadge = p.terminateTLS ? " [TLS Terminated]" : ""
                lines.append("• ID: \(p.id)")
                lines.append("  \(statusBadge)\(tlsBadge) localhost:\(p.localPort) ➔ \(p.remoteHost):\(p.remotePort)")
            }
            return lines.joined(separator: "\n")

        case "add_remote_proxy":
            guard let localPort = arguments["localPort"] as? Int else {
                throw TailscaleClientError.jsonParsingFailed("Missing required parameter 'localPort'")
            }
            guard let remoteHost = arguments["remoteHost"] as? String, !remoteHost.isEmpty else {
                throw TailscaleClientError.jsonParsingFailed("Missing required parameter 'remoteHost'")
            }
            let remotePort = arguments["remotePort"] as? Int ?? 80
            let terminateTLS = arguments["terminateTLS"] as? Bool ?? false

            let proxy = RemoteProxy(
                localPort: localPort,
                remoteHost: remoteHost,
                remotePort: remotePort,
                terminateTLS: terminateTLS,
                enabled: true
            )
            try configManager.addRemoteProxy(proxy)
            forwarder.startConfiguredProxies(configManager.load())

            let isRunning = forwarder.isProxyRunning(id: proxy.id)
            let modeDesc = terminateTLS ? " (TLS Terminated: Plain HTTP localhost ➔ HTTPS remote)" : ""
            return "✓ Remote proxy configured (ID: \(proxy.id)):\n  Local:  localhost:\(localPort)\n  Remote: \(remoteHost):\(remotePort)\(modeDesc)\n  Status: \(isRunning ? "Active and listening" : "Saved in configuration")"

        case "remove_remote_proxy":
            let config = configManager.load()
            var targetID: String? = arguments["id"] as? String
            if targetID == nil, let localPort = arguments["localPort"] as? Int {
                targetID = config.remoteProxies.first(where: { $0.localPort == localPort })?.id
            }
            guard let id = targetID else {
                return "✗ No remote proxy found matching the specified port or ID."
            }
            try configManager.removeRemoteProxy(id: id)
            forwarder.startConfiguredProxies(configManager.load())
            return "✓ Remote proxy removed (ID: \(id))."

        case "toggle_remote_proxy":
            let config = configManager.load()
            var targetID: String? = arguments["id"] as? String
            if targetID == nil, let localPort = arguments["localPort"] as? Int {
                targetID = config.remoteProxies.first(where: { $0.localPort == localPort })?.id
            }
            guard let id = targetID else {
                return "✗ No remote proxy found matching the specified port or ID."
            }
            try configManager.toggleRemoteProxy(id: id)
            let updated = configManager.load()
            forwarder.startConfiguredProxies(updated)
            let isEnabled = updated.remoteProxies.first(where: { $0.id == id })?.enabled ?? false
            return "✓ Remote proxy (ID: \(id)) is now \(isEnabled ? "enabled" : "disabled")."

        case "get_config":
            let config = configManager.load()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(config), let json = String(data: data, encoding: .utf8) {
                return json
            }
            return "{}"

        case "update_config":
            var config = configManager.load()
            if let s = arguments["socks5Port"] as? Int {
                config.socks5Port = s
            }
            if let h = arguments["httpProxyPort"] as? Int {
                config.httpProxyPort = h
            }
            if let a = arguments["autoStart"] as? Bool {
                config.autoStart = a
            }
            if let m = arguments["mcpPort"] as? Int {
                config.mcpPort = m
            }
            if let e = arguments["mcpEnabled"] as? Bool {
                config.mcpEnabled = e
            }
            try configManager.save(config)
            return "✓ Configuration updated successfully."

        default:
            throw TailscaleClientError.jsonParsingFailed("Unknown tool name '\(name)'")
        }
    }
}
