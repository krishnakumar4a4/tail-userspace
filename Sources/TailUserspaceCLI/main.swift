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
      
    SERVE COMMANDS (Local Port -> Tailnet HTTPS):
      serve list         List all configured Inbound Tailscale Serve routes
      serve add <localPort> [--serve-port <port>] [--proto <https|http|tcp>]
                         Expose a local port to the tailnet via Tailscale Serve
      serve remove <localPort>
                         Remove a configured Tailscale Serve route
      serve reset        Reset all active Tailscale Serve routes
      
    PROXY COMMANDS (Tailnet Route -> Localhost Port):
      proxy list         List all configured Outbound Remote Proxies
      proxy add <localPort> <remoteHost:remotePort>
                         Forward a local port to a remote tailnet host via SOCKS5
      proxy remove <localPort>
                         Remove a configured Outbound Remote Proxy
                         
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
        if config.serveRoutes.isEmpty {
            print("  (None configured)")
        } else {
            for route in config.serveRoutes {
                let state = route.enabled ? "✓ Enabled" : "○ Disabled"
                let targetURL = status.selfDNSName.isEmpty ? "your-node.ts.net" : status.selfDNSName
                print("  [\(state)] localhost:\(route.localPort) ➔ https://\(targetURL):\(route.servePort)\(route.path)")
            }
        }

        print("\n--- Outbound Remote Proxies (Tailnet -> Local) ---")
        if config.remoteProxies.isEmpty {
            print("  (None configured)")
        } else {
            for proxy in config.remoteProxies {
                let state = proxy.enabled ? "✓ Active" : "○ Inactive"
                print("  [\(state)] localhost:\(proxy.localPort) ➔ \(proxy.remoteHost):\(proxy.remotePort)")
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

    default:
        print("Unknown command '\(subcommand)'")
        printUsage()
        exit(1)
    }
}

func handleServeCommand(_ args: [String], configManager: ConfigManager, client: TailscaleClient) {
    guard let action = args.first else {
        print("Usage: tail-userspace serve [list|add|remove|reset]")
        return
    }

    switch action {
    case "list":
        let config = configManager.load()
        let status = client.getStatus()
        print("Configured Serve Routes:")
        for r in config.serveRoutes {
            let state = r.enabled ? "Active" : "Disabled"
            let host = status.selfDNSName.isEmpty ? "your-node.ts.net" : status.selfDNSName
            print("  • [\(state)] localhost:\(r.localPort) ➔ https://\(host):\(r.servePort)\(r.path)")
        }

    case "add":
        guard args.count >= 2, let localPort = Int(args[1]) else {
            print("Usage: tail-userspace serve add <localPort> [--serve-port <port>]")
            return
        }
        var servePort = 443
        if let portIdx = args.firstIndex(of: "--serve-port"), portIdx + 1 < args.count, let p = Int(args[portIdx + 1]) {
            servePort = p
        }
        let route = ServeRoute(localPort: localPort, servePort: servePort)
        do {
            try configManager.addServeRoute(route)
            print("✓ Saved serve route: localhost:\(localPort) ➔ port \(servePort)")
            if client.getStatus().isOnline {
                try client.applyServeRoute(route)
                print("✓ Applied to live Tailscale daemon.")
            } else {
                print("ℹ Route saved. Will be applied automatically when daemon is online.")
            }
        } catch {
            print("✗ Failed to save serve route: \(error.localizedDescription)")
        }

    case "remove":
        guard args.count >= 2, let localPort = Int(args[1]) else {
            print("Usage: tail-userspace serve remove <localPort>")
            return
        }
        let config = configManager.load()
        if let route = config.serveRoutes.first(where: { $0.localPort == localPort }) {
            try? configManager.removeServeRoute(id: route.id)
            print("✓ Removed serve route for port \(localPort).")
        } else {
            print("✗ No route found for port \(localPort).")
        }

    case "reset":
        do {
            try client.resetServe()
            print("✓ Tailscale serve configuration reset.")
        } catch {
            print("✗ Failed: \(error.localizedDescription)")
        }

    default:
        print("Unknown serve action '\(action)'")
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
        print("Configured Outbound Remote Proxies:")
        for p in config.remoteProxies {
            let state = p.enabled ? "Active" : "Disabled"
            print("  • [\(state)] localhost:\(p.localPort) ➔ \(p.remoteHost):\(p.remotePort)")
        }

    case "add":
        guard args.count >= 3, let localPort = Int(args[1]) else {
            print("Usage: tail-userspace proxy add <localPort> <remoteHost:remotePort>")
            return
        }
        let targetParts = args[2].split(separator: ":")
        let remoteHost = String(targetParts[0])
        var remotePort = 80
        if targetParts.count == 2, let p = Int(targetParts[1]) {
            remotePort = p
        }
        let proxy = RemoteProxy(localPort: localPort, remoteHost: remoteHost, remotePort: remotePort)
        do {
            try configManager.addRemoteProxy(proxy)
            print("✓ Saved remote proxy: localhost:\(localPort) ➔ \(remoteHost):\(remotePort)")
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
