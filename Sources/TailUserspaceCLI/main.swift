import Foundation
import TailUserspaceCore

func printUsage() {
    print("""
    TailUserspace CLI - Lightweight macOS Tailscale Userspace Manager
    
    USAGE:
      tail-userspace [options] <subcommand> [subcommand-options]
      
    DAEMON COMMANDS:
      start              Start the unprivileged userspace tailscaled daemon
      stop               Stop the userspace tailscaled daemon
      status             Show live daemon, Tailscale, Serve, and Proxy status
      up [flags]         Connect local node to Tailscale (opens auth in browser if needed)
      down               Disconnect local node from Tailscale network
      env                Print shell export commands for SOCKS5 and HTTP proxy
      logs               Print path to tailscaled log file
      
    SERVE COMMANDS (Local Port / URL -> Tailnet HTTPS / TCP):
      serve <target> [flags]
                         Expose a local service to your tailnet (foreground attached mode)
      serve add <target> [flags]
                         Add and configure a serve route (supports --bg for background)
      serve remove <target|port> [--set-path=<path>]
                         Remove a configured serve route and unmount it from daemon
      serve off [flags]  Turn off a specific serve handler or port on the daemon
      serve status [--json]
                         View live serve configuration and discrepancy report
      serve list         List all configured persistent serve routes
      serve reset        Reset all active Tailscale Serve routes
      serve reapply      Reapply and synchronize configured routes to the live daemon

    SERVE TARGETS & FLAGS:
      <target>           Port (3000), URL (http://localhost:3000/api), or
                         insecure HTTPS (https+insecure://localhost:8443)
      --https=<port>     Expose HTTPS endpoint at port (default: 443)
      --http=<port>      Expose plain HTTP endpoint at port (default: 80)
      --tcp=<port>       Expose raw TCP forwarder at port
      --tls-terminated-tcp=<port>
                         Expose TLS-terminated TCP forwarder at port
      --set-path=<path>  Mount handler under a subpath (e.g. /api or /)
      --proxy-protocol=<1|2>
                         Send PROXY protocol header (v1 or v2) to upstream
      --bg               Run in background and save permanently to config.json
      
    PROXY COMMANDS (Tailnet Route -> Localhost Port):
      proxy list         List all configured Outbound Remote Proxies
      proxy add <localPort> <remoteHost:remotePort> [--tls]
                         Forward a local port to a remote tailnet host via SOCKS5
                         Use --tls to terminate remote TLS and expose as plain HTTP locally
      proxy remove <localPort>
                         Remove a configured Outbound Remote Proxy

    AI / MCP COMMANDS (Model Context Protocol):
      mcp                Start JSON-RPC 2.0 MCP server on stdio for AI assistants
                         (Claude Desktop, Cursor, Antigravity, VS Code, Zed)
                         Pass --help to view configuration snippets and available tools
                         
    GLOBAL OPTIONS:
      -v, --verbose      Enable verbose output (detailed steps, diagnostic paths)
      -vv, --debug       Enable full debug trace (raw CLI I/O, process exit codes, JSON dumps)
      -h, --help         Show this help message
    """)
}

func main() {
    let rawArgs = Array(CommandLine.arguments.dropFirst())
    var verbosityLevel = VerbosityLevel.normal
    var filteredArgs: [String] = []

    for arg in rawArgs {
        if arg == "-vv" || arg == "--debug" {
            verbosityLevel = .debug
        } else if arg == "-v" || arg == "--verbose" {
            if verbosityLevel < .verbose {
                verbosityLevel = .verbose
            }
        } else {
            filteredArgs.append(arg)
        }
    }

    Logger.shared.level = verbosityLevel
    Logger.shared.debug("Logger initialized with level: \(verbosityLevel)")

    guard let subcommand = filteredArgs.first, subcommand != "-h", subcommand != "--help" else {
        printUsage()
        return
    }

    let subArgs = Array(filteredArgs.dropFirst())
    let configManager = ConfigManager.shared
    let supervisor = DaemonSupervisor.shared
    let client = TailscaleClient.shared
    let forwarder = SOCKS5Forwarder.shared

    switch subcommand {
    case "start":
        do {
            let config = configManager.load()
            Logger.shared.info("Starting userspace tailscaled...")
            let pid = try supervisor.start(config: config)
            print("✓ Tailscale userspace daemon started (PID: \(pid))")
            print("  Socket:       \(PathConstants.socketPath)")
            print("  SOCKS5 Proxy: 127.0.0.1:\(config.socks5Port)")
            print("  HTTP Proxy:   127.0.0.1:\(config.httpProxyPort)")

            // Start forwarders
            forwarder.startConfiguredProxies(config)

            // Re-apply serve routes if already online
            try client.reapplyConfiguredServeRoutes(config)
        } catch {
            print("✗ Error starting daemon: \(error.localizedDescription)")
            exit(1)
        }

    case "stop":
        do {
            Logger.shared.info("Stopping proxies and daemon...")
            forwarder.stopAll()
            try supervisor.stop()
            print("✓ Tailscale userspace daemon stopped.")
        } catch {
            print("✗ Error stopping daemon: \(error.localizedDescription)")
            exit(1)
        }

    case "status":
        let status = client.getStatus()
        let config = configManager.load()

        print("=== Tailscale Userspace Status ===")
        if status.isProcessRunning, let pid = status.pid {
            print("● Daemon Process:  Running (PID: \(pid))")
        } else {
            print("○ Daemon Process:  Stopped")
        }
        print("  Backend State:   \(status.backendState)")
        if !status.selfName.isEmpty {
            print("  Machine Name:    \(status.selfName)")
        }
        if !status.selfDNSName.isEmpty {
            print("  Tailnet Domain:  \(status.selfDNSName)")
        }
        if !status.tailscaleIPs.isEmpty {
            print("  Tailscale IPs:   \(status.tailscaleIPs.joined(separator: ", "))")
        }
        if let authURL = status.authURL, !authURL.isEmpty {
            print("\n  ╔══════════════════════════════════════════════════════════════════════════╗")
            print("  ║ Tailscale Login URL Required:                                            ║")
            print("  ║ 👉 \(authURL)")
            print("  ╚══════════════════════════════════════════════════════════════════════════╝\n")
        }
        print("  SOCKS5 Proxy:    127.0.0.1:\(config.socks5Port)")
        print("  HTTP Proxy:      127.0.0.1:\(config.httpProxyPort)")

        print("\n--- Inbound Serve Routes (Local -> Tailnet) ---")
        let targetHost = status.selfDNSName.isEmpty ? "your-node.ts.net" : status.selfDNSName
        let discrepancies = client.checkServeDiscrepancies(config: config)
        let activeEphemeral = client.cleanupStaleEphemeralSessionsAndUnmount()

        let daemonOnlyDiscrepancies = discrepancies.filter { $0.kind == .daemonOnly }
        let hasNoRoutes = config.serveRoutes.isEmpty && daemonOnlyDiscrepancies.isEmpty && activeEphemeral.isEmpty

        if hasNoRoutes {
            print("  (None configured)")
        } else {
            for route in config.serveRoutes {
                let badge: String
                let note: String
                if let disc = discrepancies.first(where: { $0.route.id == route.id }) {
                    switch disc.kind {
                    case .inSync:
                        badge = "[✓ In Sync]"
                        note = ""
                    case .notOnDaemon:
                        badge = "[⚠️ Not on Daemon]"
                        note = " (Offline/Missing on live daemon)"
                    case .mismatch:
                        badge = "[🔄 Target Mismatch]"
                        note = " (Live daemon points to: \(disc.liveTarget ?? ""))"
                    case .daemonOnly, .cliEphemeral:
                        badge = "[ℹ️ Live Route]"
                        note = ""
                    }
                } else {
                    badge = route.enabled ? "[✓ Active]" : "[○ Disabled]"
                    note = ""
                }

                let protoPrefix = route.proto == "https" ? "https" : route.proto == "http" ? "http" : "tcp"
                let paddedBadge = badge.padding(toLength: 20, withPad: " ", startingAt: 0)
                print("  \(paddedBadge) \(route.target) ➔ \(protoPrefix)://\(targetHost):\(route.servePort)\(route.path)\(note)")
            }

            // Print any ephemeral CLI routes
            for eph in activeEphemeral {
                let protoPrefix = eph.route.proto == "https" ? "https" : eph.route.proto == "http" ? "http" : "tcp"
                let paddedBadge = "[⚡ CLI Ephemeral]".padding(toLength: 20, withPad: " ", startingAt: 0)
                print("  \(paddedBadge) \(eph.route.target) ➔ \(protoPrefix)://\(targetHost):\(eph.route.servePort)\(eph.route.path) (PID: \(eph.pid))")
            }

            // Print unmanaged daemon-only routes
            for disc in daemonOnlyDiscrepancies {
                let protoPrefix = disc.route.proto == "https" ? "https" : disc.route.proto == "http" ? "http" : "tcp"
                let liveTgt = disc.liveTarget ?? disc.route.target
                let paddedBadge = "[ℹ️ Daemon Only]".padding(toLength: 20, withPad: " ", startingAt: 0)
                print("  \(paddedBadge) \(liveTgt) ➔ \(protoPrefix)://\(targetHost):\(disc.route.servePort)\(disc.route.path) (Unmanaged)")
            }

            let hasErrors = discrepancies.contains { $0.kind == .notOnDaemon || $0.kind == .mismatch }
            if hasErrors && status.isOnline {
                print("\n  ⚠️  Discrepancy detected between config.json and live daemon.")
                print("      Run 'tail-userspace serve reapply' to synchronize configured routes to the live daemon.")
            }
        }

        print("\n--- Outbound Remote Proxies (Local <- Tailnet) ---")
        if config.remoteProxies.isEmpty {
            print("  (None configured)")
        } else {
            for proxy in config.remoteProxies {
                let state = proxy.enabled ? "✓ Active" : "○ Inactive"
                let tlsBadge = proxy.terminateTLS ? " [TLS]" : ""
                print("  [\(state)\(tlsBadge)] localhost:\(proxy.localPort) ← \(proxy.remoteHost):\(proxy.remotePort)")
            }
        }

        if Logger.shared.level >= .verbose {
            print("\n--- Diagnostic Paths (-v) ---")
            print("  Base Directory:  \(PathConstants.baseDirectory.path)")
            print("  Socket Path:     \(PathConstants.socketPath)")
            print("  State Path:      \(PathConstants.statePath)")
            print("  Config Path:     \(PathConstants.configPath)")
            print("  Logs Path:       \(PathConstants.logFilePath)")
            print("  PID File:        \(PathConstants.pidFilePath)")
        }

        if Logger.shared.level >= .debug {
            print("\n--- Raw JSON Status (-vv) ---")
            if let rawJson = try? client.runCommand(["status", "--json"], timeout: 5.0) {
                print(rawJson)
            } else {
                print("  (Unable to retrieve raw JSON status)")
            }
        }

    case "up":
        print("Connecting to Tailscale network...")
        do {
            try client.connect(
                extraArgs: subArgs,
                timeout: 180.0,
                autoOpenBrowser: true,
                onAuthURL: { url in
                    print("\n" + String(repeating: "=", count: 76))
                    print("  Tailscale Authentication Required")
                    print("  👉 \(url.absoluteString)")
                    print(String(repeating: "=", count: 76))
                    print("  Opening URL in your default browser...")
                    print("  (If browser did not open automatically, copy and paste the link above)")
                    print("  Waiting for authentication in browser... (Press Ctrl+C to cancel)\n")
                },
                onOutput: { chunk in
                    if Logger.shared.level >= .verbose {
                        print(chunk, terminator: "")
                        fflush(stdout)
                    }
                }
            )
            let status = client.getStatus()
            print("✓ Connected to Tailscale network!")
            if !status.selfDNSName.isEmpty {
                print("  Node DNS:   \(status.selfDNSName)")
            }
            if !status.tailscaleIPs.isEmpty {
                print("  Tailnet IP: \(status.tailscaleIPs.joined(separator: ", "))")
            }
        } catch {
            print("✗ Connection failed: \(error.localizedDescription)")
            exit(1)
        }

    case "down":
        do {
            Logger.shared.info("Disconnecting tailscale node...")
            try client.disconnect()
            print("✓ Disconnected from Tailscale network.")
        } catch {
            print("✗ Failed: \(error.localizedDescription)")
            exit(1)
        }

    case "env":
        let config = configManager.load()
        print("export ALL_PROXY=socks5://127.0.0.1:\(config.socks5Port)")
        print("export HTTP_PROXY=http://127.0.0.1:\(config.httpProxyPort)")
        print("export HTTPS_PROXY=http://127.0.0.1:\(config.httpProxyPort)")

    case "logs":
        print(PathConstants.logFilePath)

    case "serve":
        handleServeCommand(subArgs, configManager: configManager, client: client)

    case "proxy":
        handleProxyCommand(subArgs, configManager: configManager, forwarder: forwarder)

    case "mcp":
        handleMCPCommand(subArgs)

    default:
        print("Unknown command '\(subcommand)'")
        printUsage()
        exit(1)
    }
}

func handleMCPCommand(_ args: [String]) {
    if args.contains("-h") || args.contains("--help") {
        print("""
        TailUserspace MCP Server - Model Context Protocol Interface

        Starts the Model Context Protocol (MCP) server for TailUserspace over standard I/O (JSON-RPC 2.0).
        Enables AI assistants (Claude Desktop, Cursor, Antigravity, VS Code, Zed) to manage daemon state,
        query tailnet connectivity, configure inbound serve routes, and establish outbound remote proxies.

        USAGE:
          tail-userspace mcp
          tail-userspace-mcp

        AI CLIENT CONFIGURATION:

        Claude Desktop (~/Library/Application Support/Claude/claude_desktop_config.json):
        {
          "mcpServers": {
            "tail-userspace": {
              "command": "tail-userspace",
              "args": ["mcp"]
            }
          }
        }

        Cursor / Antigravity / Gemini CLI (mcp.json):
        {
          "mcpServers": {
            "tail-userspace": {
              "command": "tail-userspace",
              "args": ["mcp"]
            }
          }
        }

        AVAILABLE TOOLS (19):
          • get_status            - Live daemon PID, backend state, IPs, domain, auth URL
          • daemon_start          - Start userspace tailscaled daemon and listeners
          • daemon_stop           - Stop daemon and proxy forwarders
          • connect               - Connect node to Tailscale network (tailscale up)
          • disconnect            - Disconnect node from Tailscale (tailscale down)
          • get_env               - Shell export variables for SOCKS5/HTTP proxy
          • get_daemon_logs       - Read recent tailscaled.log lines
          • list_serve_routes     - List inbound serve routes and sync states
          • add_serve_route       - Expose local port/URL to tailnet with HTTPS
          • remove_serve_route    - Unmount and delete inbound serve route
          • reapply_serve_routes  - Re-sync routes to live daemon
          • reset_serve           - Reset all active Tailscale Serve endpoints
          • get_serve_status      - Live daemon serve status output
          • list_remote_proxies   - List outbound SOCKS5 remote proxies
          • add_remote_proxy      - Map local port to remote tailnet service
          • remove_remote_proxy   - Remove an outbound remote proxy
          • toggle_remote_proxy   - Enable or disable an outbound remote proxy
          • get_config            - Inspect persistent config.json
          • update_config         - Update SOCKS5/HTTP proxy ports or autoStart

        AVAILABLE RESOURCES (5):
          • tailuserspace://status   - Live daemon & connection state JSON
          • tailuserspace://config   - Current config.json
          • tailuserspace://serve    - Inbound serve routes & discrepancy report
          • tailuserspace://proxies  - Outbound remote proxies & listener states
          • tailuserspace://logs     - Recent tailscaled daemon logs

        AVAILABLE PROMPTS (3):
          • diagnose                - Full diagnostic analysis of instance
          • expose-service          - Guide to expose a local service via Serve
          • tunnel-remote-service   - Guide to tunnel a remote tailnet service locally
        """)
        return
    }

    MCPServer.shared.runStdio()
}

struct ParsedServeOptions {
    var target: String?
    var servePort: Int = 443
    var proto: String = "https"
    var path: String = "/"
    var proxyProtocol: Int? = nil
    var isBackground: Bool = false
    var isOff: Bool = false
    var isReset: Bool = false
    var isReapply: Bool = false
    var isStatus: Bool = false
    var isList: Bool = false
    var isJson: Bool = false
}

func parseServeArgs(_ args: [String]) -> ParsedServeOptions {
    var opts = ParsedServeOptions()
    var i = 0
    var positional: [String] = []

    while i < args.count {
        let arg = args[i]

        if arg == "status" {
            opts.isStatus = true
        } else if arg == "reset" {
            opts.isReset = true
        } else if arg == "reapply" {
            opts.isReapply = true
        } else if arg == "list" {
            opts.isList = true
        } else if arg == "off" {
            opts.isOff = true
        } else if arg == "--json" {
            opts.isJson = true
        } else if arg == "--bg" || arg == "--background" {
            opts.isBackground = true
        } else if arg.hasPrefix("--https") {
            opts.proto = "https"
            if arg.contains("=") {
                let parts = arg.split(separator: "=", maxSplits: 1)
                if parts.count == 2, let p = Int(parts[1]) {
                    opts.servePort = p
                }
            } else if i + 1 < args.count, let p = Int(args[i + 1]) {
                opts.servePort = p
                i += 1
            } else {
                opts.servePort = 443
            }
        } else if arg.hasPrefix("--http") {
            opts.proto = "http"
            if arg.contains("=") {
                let parts = arg.split(separator: "=", maxSplits: 1)
                if parts.count == 2, let p = Int(parts[1]) {
                    opts.servePort = p
                }
            } else if i + 1 < args.count, let p = Int(args[i + 1]) {
                opts.servePort = p
                i += 1
            } else {
                opts.servePort = 80
            }
        } else if arg.hasPrefix("--tcp") {
            opts.proto = "tcp"
            if arg.contains("=") {
                let parts = arg.split(separator: "=", maxSplits: 1)
                if parts.count == 2, let p = Int(parts[1]) {
                    opts.servePort = p
                }
            } else if i + 1 < args.count, let p = Int(args[i + 1]) {
                opts.servePort = p
                i += 1
            }
        } else if arg.hasPrefix("--tls-terminated-tcp") {
            opts.proto = "tls-terminated-tcp"
            if arg.contains("=") {
                let parts = arg.split(separator: "=", maxSplits: 1)
                if parts.count == 2, let p = Int(parts[1]) {
                    opts.servePort = p
                }
            } else if i + 1 < args.count, let p = Int(args[i + 1]) {
                opts.servePort = p
                i += 1
            }
        } else if arg.hasPrefix("--set-path") {
            if arg.contains("=") {
                let parts = arg.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    opts.path = String(parts[1])
                }
            } else if i + 1 < args.count {
                opts.path = args[i + 1]
                i += 1
            }
        } else if arg.hasPrefix("--proxy-protocol") {
            if arg.contains("=") {
                let parts = arg.split(separator: "=", maxSplits: 1)
                if parts.count == 2, let v = Int(parts[1]) {
                    opts.proxyProtocol = v
                }
            } else if i + 1 < args.count, let v = Int(args[i + 1]) {
                opts.proxyProtocol = v
                i += 1
            }
        } else if !arg.hasPrefix("-") {
            positional.append(arg)
        }
        i += 1
    }

    if !opts.path.hasPrefix("/") {
        opts.path = "/" + opts.path
    }

    if let firstPos = positional.first {
        if firstPos != "add" && firstPos != "remove" && firstPos != "off" && firstPos != "list" && firstPos != "status" && firstPos != "reset" && firstPos != "reapply" {
            opts.target = firstPos
        } else if positional.count > 1 {
            opts.target = positional[1]
        }
    }

    return opts
}

func handleServeCommand(_ args: [String], configManager: ConfigManager, client: TailscaleClient) {
    if args.isEmpty || args.contains("-h") || args.contains("--help") {
        print("""
        Usage:
          tail-userspace serve <target> [flags]
          tail-userspace serve add <target> [flags]
          tail-userspace serve remove <target|port> [--set-path=<path>]
          tail-userspace serve off [flags]
          tail-userspace serve status [--json]
          tail-userspace serve list
          tail-userspace serve reset
          tail-userspace serve reapply

        Targets:
          <port>            Local port number (e.g. 3000, 8080)
          <url>             Full HTTP/HTTPS URL (e.g. http://localhost:3000/api)
          <insecure-url>    Self-signed HTTPS backend (e.g. https+insecure://localhost:8443)

        Flags:
          --https=<port>    Expose HTTPS endpoint at port (default: 443)
          --http=<port>     Expose HTTP endpoint at port (default: 80)
          --tcp=<port>      Expose raw TCP forwarder at port
          --tls-terminated-tcp=<port>
                            Expose TLS-terminated TCP forwarder at port
          --set-path=<path> Mount handler under subpath (default: /)
          --proxy-protocol=<1|2>
                            Send PROXY protocol header
          --bg              Run in background and save permanently to config.json
        """)
        return
    }

    let opts = parseServeArgs(args)

    if opts.isStatus {
        let output = client.getServeStatus(json: opts.isJson)
        print(output)
        if !opts.isJson {
            let config = configManager.load()
            let disc = client.checkServeDiscrepancies(config: config)
            let errors = disc.filter { $0.kind == .notOnDaemon || $0.kind == .mismatch }
            if !errors.isEmpty {
                print("\n⚠️ Discrepancy detected with config.json:")
                for e in errors {
                    print("  • \(e.message)")
                }
                print("Run 'tail-userspace serve reapply' to synchronize routes.")
            }
        }
        return
    }

    if opts.isReset {
        do {
            try client.resetServe()
            print("✓ Tailscale serve configuration reset.")
        } catch {
            print("✗ Failed to reset serve: \(error.localizedDescription)")
            exit(1)
        }
        return
    }

    if opts.isReapply {
        let config = configManager.load()
        let status = client.getStatus()
        guard status.isOnline else {
            print("✗ Cannot reapply: Tailscale daemon is offline. Run 'tail-userspace start' first.")
            exit(1)
        }
        do {
            try client.reapplyConfiguredServeRoutes(config)
            let count = config.serveRoutes.filter { $0.enabled }.count
            print("✓ Reapplied \(count) configured serve route(s) to live daemon.")
        } catch {
            print("✗ Failed to reapply routes: \(error.localizedDescription)")
            exit(1)
        }
        return
    }

    if opts.isList {
        let config = configManager.load()
        let status = client.getStatus()
        let host = status.selfDNSName.isEmpty ? "your-node.ts.net" : status.selfDNSName
        let disc = client.checkServeDiscrepancies(config: config)

        print("Configured Serve Routes:")
        if config.serveRoutes.isEmpty {
            print("  (None configured)")
        } else {
            for r in config.serveRoutes {
                let d = disc.first(where: { $0.route.id == r.id })
                let statusBadge: String
                switch d?.kind {
                case .inSync: statusBadge = "✓ In Sync"
                case .notOnDaemon: statusBadge = "⚠️ Not on Daemon"
                case .mismatch: statusBadge = "🔄 Mismatch"
                default: statusBadge = r.enabled ? "Active" : "Disabled"
                }
                print("  • [\(statusBadge)] \(r.target) ➔ \(r.proto)://\(host):\(r.servePort)\(r.path)")
            }
        }
        return
    }

    if opts.isOff || args.contains("remove") || args.contains("off") {
        let config = configManager.load()
        if let tgt = opts.target {
            if let route = config.serveRoutes.first(where: {
                $0.target == tgt ||
                "\($0.localPort)" == tgt ||
                $0.target.contains(":\(tgt)") ||
                $0.target.hasSuffix(":\(tgt)")
            }) {
                try? client.removeServeRouteLive(route)
                try? configManager.removeServeRoute(id: route.id)
                print("✓ Removed and unmounted serve route for \(route.target) (\(route.proto)://:\(route.servePort)\(route.path)).")
                return
            }
        }

        // Fallback: match by endpoint port and path (e.g. serve off --https=443 --set-path=/api)
        if let route = config.serveRoutes.first(where: {
            $0.servePort == opts.servePort && $0.path == opts.path && (opts.proto == $0.proto)
        }) {
            try? client.removeServeRouteLive(route)
            try? configManager.removeServeRoute(id: route.id)
            print("✓ Removed and unmounted serve route for \(route.target) (\(route.proto)://:\(route.servePort)\(route.path)).")
            return
        }

        let route = ServeRoute(
            target: opts.target ?? "",
            servePort: opts.servePort,
            proto: opts.proto,
            path: opts.path
        )
        try? client.removeServeRouteLive(route)
        print("✓ Turned off serve endpoint on \(route.proto)://:\(route.servePort)\(route.path).")
        return
    }

    // Adding/running a serve route
    guard let rawTarget = opts.target, !rawTarget.isEmpty else {
        print("✗ Target is required. E.g.: 'tail-userspace serve 3000' or 'tail-userspace serve --bg http://localhost:8080/api'")
        exit(1)
    }

    var normalizedTarget = rawTarget
    if normalizedTarget.hasPrefix("localhost:") || normalizedTarget.hasPrefix("127.0.0.1:") {
        normalizedTarget = "http://" + normalizedTarget
    }

    let route = ServeRoute(
        target: normalizedTarget,
        servePort: opts.servePort,
        proto: opts.proto,
        path: opts.path,
        enabled: true,
        proxyProtocol: opts.proxyProtocol
    )

    let status = client.getStatus()
    let host = status.selfDNSName.isEmpty ? "your-node.ts.net" : status.selfDNSName

    if opts.isBackground {
        do {
            try configManager.addServeRoute(route)
            print("✓ Saved serve route to config.json")
            if status.isOnline {
                try client.applyServeRoute(route, background: true)
                print("✓ Applied to live Tailscale daemon:")
                print("  Available within your tailnet:")
                print("  \(route.proto)://\(host):\(route.servePort)\(route.path)")
                print("  |-- proxies to \(route.target)")
            } else {
                print("ℹ Route saved. Will be applied automatically when daemon is online.")
            }
        } catch {
            print("✗ Failed to save serve route: \(error.localizedDescription)")
            exit(1)
        }
    } else {
        // Foreground attached mode
        guard status.isOnline else {
            print("✗ Cannot start foreground serve: Tailscale daemon is offline.")
            print("  Run 'tail-userspace start' first, or pass '--bg' to save the route for later.")
            exit(1)
        }

        do {
            try client.applyServeRoute(route, background: true)
        } catch {
            print("✗ Failed to apply serve route on daemon: \(error.localizedDescription)")
            exit(1)
        }

        let session = EphemeralServeSession(id: route.id, pid: getpid(), route: route, createdAt: Date())
        try? configManager.saveEphemeralSession(session)

        print("Available within your tailnet:\n")
        print("  \(route.proto)://\(host):\(route.servePort)\(route.path)")
        print("  |-- proxies to \(route.target)\n")
        print("⚡ [CLI] Foreground serve session active (PID: \(getpid()))")
        print("Press Ctrl+C to exit and unmount this serve endpoint.\n")

        var isCleanedUp = false
        let cleanup = {
            guard !isCleanedUp else { return }
            isCleanedUp = true
            print("\nUnmounting serve endpoint...")
            try? client.removeServeRouteLive(route)
            try? configManager.removeEphemeralSession(id: session.id)
            print("✓ Serve endpoint unmounted.")
            exit(0)
        }

        let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigint.setEventHandler(handler: cleanup)
        sigterm.setEventHandler(handler: cleanup)
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)
        sigint.resume()
        sigterm.resume()

        dispatchMain()
    }
}

func handleProxyCommand(_ args: [String], configManager: ConfigManager, forwarder: SOCKS5Forwarder) {
    guard let action = args.first else {
        print("Usage: tail-userspace proxy [list|add|remove]")
        return
    }

    switch action {
    case "list":
        let config = configManager.load()
        print("Configured Outbound Remote Proxies (Local <- Tailnet):")
        for p in config.remoteProxies {
            let state = p.enabled ? "Active" : "Disabled"
            let tlsBadge = p.terminateTLS ? " [TLS]" : ""
            print("  • [\(state)\(tlsBadge)] localhost:\(p.localPort) ← \(p.remoteHost):\(p.remotePort)")
        }

    case "add":
        guard args.count >= 3, let localPort = Int(args[1]) else {
            print("Usage: tail-userspace proxy add <localPort> <remoteHost:remotePort> [--tls]")
            return
        }
        let targetParts = args[2].split(separator: ":")
        let remoteHost = String(targetParts[0])
        var remotePort = 80
        if targetParts.count == 2, let p = Int(targetParts[1]) {
            remotePort = p
        }

        let terminateTLS = args.contains("--tls") || args.contains("--terminate-tls")

        let proxy = RemoteProxy(localPort: localPort, remoteHost: remoteHost, remotePort: remotePort, terminateTLS: terminateTLS)
        do {
            try configManager.addRemoteProxy(proxy)
            let modeDesc = terminateTLS ? " [TLS: Plain HTTP locally ➔ HTTPS upstream]" : ""
            print("✓ Saved remote proxy: localhost:\(localPort) ← \(remoteHost):\(remotePort)\(modeDesc)")
            let config = configManager.load()
            forwarder.startConfiguredProxies(config)
            print("✓ Proxy forwarder active on localhost:\(localPort)")
        } catch {
            print("✗ Failed to save proxy: \(error.localizedDescription)")
        }

    case "remove":
        guard args.count >= 2, let localPort = Int(args[1]) else {
            print("Usage: tail-userspace proxy remove <localPort>")
            return
        }
        let config = configManager.load()
        if let proxy = config.remoteProxies.first(where: { $0.localPort == localPort }) {
            try? configManager.removeRemoteProxy(id: proxy.id)
            forwarder.startConfiguredProxies(configManager.load())
            print("✓ Removed remote proxy for port \(localPort).")
        } else {
            print("✗ No proxy found for port \(localPort).")
        }

    default:
        print("Unknown proxy action '\(action)'")
    }
}

main()
