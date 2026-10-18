import Foundation

/// Defines all available MCP prompts and generates contextual prompt messages
public struct MCPPrompts {

    public static let allPrompts: [MCPPrompt] = [
        MCPPrompt(
            name: "diagnose",
            description: "Inspect TailUserspace daemon health, connectivity, serve routes, and active proxies to diagnose connection or routing issues.",
            arguments: []
        ),
        MCPPrompt(
            name: "expose-service",
            description: "Guide configuration to securely expose a local web service, container, or dev port to your tailnet via Tailscale Serve.",
            arguments: [
                [
                    "name": "target",
                    "description": "Local service port or URL (e.g. 3000 or http://localhost:8080)",
                    "required": true
                ],
                [
                    "name": "path",
                    "description": "Optional subpath to mount under (e.g. / or /api)",
                    "required": false
                ]
            ]
        ),
        MCPPrompt(
            name: "tunnel-remote-service",
            description: "Guide setting up a local SOCKS5 port forwarder to reach a remote tailnet service (NAS, database, web UI) locally.",
            arguments: [
                [
                    "name": "remoteHost",
                    "description": "Hostname or IP of the remote tailnet node (e.g. my-nas.ts.net)",
                    "required": true
                ],
                [
                    "name": "remotePort",
                    "description": "Port on the remote node (e.g. 80, 5432, 9443)",
                    "required": true
                ],
                [
                    "name": "localPort",
                    "description": "Local port on your Mac to bind (e.g. 8080)",
                    "required": true
                ]
            ]
        )
    ]

    /// Generates prompt text and messages for the requested prompt
    public static func get(
        name: String,
        arguments: [String: Any],
        client: TailscaleClient = .shared,
        supervisor: DaemonSupervisor = .shared,
        configManager: ConfigManager = .shared
    ) throws -> (description: String, messages: [[String: Any]]) {
        switch name {
        case "diagnose":
            let status = client.getStatus()
            let config = configManager.load()
            let (running, pid) = supervisor.isRunning()
            let discrepancies = client.checkServeDiscrepancies(config: config)

            let promptContent = """
            Please analyze the health and diagnostic state of this TailUserspace instance:

            DAEMON STATUS:
            • Process Running: \(running) \(pid != nil ? "(PID: \(pid!))" : "")
            • Backend State:   \(status.backendState)
            • Self Node Name:  \(status.selfName.isEmpty ? "None" : status.selfName)
            • MagicDNS Domain: \(status.selfDNSName.isEmpty ? "None" : status.selfDNSName)
            • Tailscale IPs:   \(status.tailscaleIPs.joined(separator: ", "))
            • Health Warnings: \(status.healthWarnings.isEmpty ? "None" : status.healthWarnings.joined(separator: "; "))

            CONFIGURED SERVE ROUTES:
            \(config.serveRoutes.map { "• \($0.target) -> \($0.proto)://:\($0.servePort)\($0.path) [Enabled: \($0.enabled)]" }.joined(separator: "\n"))

            SERVE DISCREPANCIES:
            \(discrepancies.map { "• [\($0.kind.rawValue)] \($0.message)" }.joined(separator: "\n"))

            OUTBOUND REMOTE PROXIES:
            \(config.remoteProxies.map { "• localhost:\($0.localPort) <- \($0.remoteHost):\($0.remotePort) [TLS: \($0.terminateTLS), Enabled: \($0.enabled)]" }.joined(separator: "\n"))

            Please identify:
            1. Is the userspace daemon healthy and connected to the tailnet?
            2. Are there any discrepancies between config.json and the live daemon serve routes?
            3. Are all expected inbound or outbound routes reachable?
            4. Recommend specific actions or tool calls (e.g., daemon_start, connect, reapply_serve_routes) if any remediation is needed.
            """

            return (
                "TailUserspace Diagnostics Analysis",
                [
                    [
                        "role": "user",
                        "content": [
                            "type": "text",
                            "text": promptContent
                        ]
                    ]
                ]
            )

        case "expose-service":
            let target = arguments["target"] as? String ?? "<target-port>"
            let path = arguments["path"] as? String ?? "/"

            let promptContent = """
            I want to expose a local service on my Mac to other nodes on my Tailscale network using Tailscale Userspace Serve.

            Parameters:
            • Local Target: \(target)
            • Mount Path:   \(path)
            • Protocol:     HTTPS (port 443 with automated Let's Encrypt TLS)

            Please check if the daemon is online using 'get_status', and if ready, invoke 'add_serve_route' with:
            - target: "\(target)"
            - servePort: 443
            - proto: "https"
            - path: "\(path)"
            - background: true

            Then verify the resulting HTTPS endpoint URL and confirm the service is accessible to authorized tailnet members.
            """

            return (
                "Expose Local Service to Tailnet via Serve",
                [
                    [
                        "role": "user",
                        "content": [
                            "type": "text",
                            "text": promptContent
                        ]
                    ]
                ]
            )

        case "tunnel-remote-service":
            let remoteHost = arguments["remoteHost"] as? String ?? "<remote-node.ts.net>"
            let remotePort = arguments["remotePort"] as? String ?? "80"
            let localPort = arguments["localPort"] as? String ?? "8080"

            let promptContent = """
            I want to tunnel a remote service on my Tailscale network to a local port on my Mac using TailUserspace SOCKS5 forwarder.

            Parameters:
            • Remote Destination: \(remoteHost):\(remotePort)
            • Local Endpoint:     localhost:\(localPort)

            Please:
            1. Verify daemon connectivity using 'get_status'.
            2. Invoke 'add_remote_proxy' with:
               - localPort: \(localPort)
               - remoteHost: "\(remoteHost)"
               - remotePort: \(remotePort)
               - terminateTLS: false (or true if the remote service uses HTTPS and we want plain HTTP locally)
            3. Verify the local port is listening and explain how I can connect to it (e.g. curl http://localhost:\(localPort)).
            """

            return (
                "Tunnel Remote Tailnet Service Locally",
                [
                    [
                        "role": "user",
                        "content": [
                            "type": "text",
                            "text": promptContent
                        ]
                    ]
                ]
            )

        default:
            throw TailscaleClientError.jsonParsingFailed("Prompt not found: '\(name)'")
        }
    }
}
