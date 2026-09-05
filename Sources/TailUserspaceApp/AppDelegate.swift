import Cocoa
import TailUserspaceCore

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var pollTimer: Timer?
    private let supervisor = DaemonSupervisor.shared
    private let client = TailscaleClient.shared
    private let configManager = ConfigManager.shared
    private let forwarder = SOCKS5Forwarder.shared

    private var currentStatus: DaemonStatus = DaemonStatus()

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon(isOnline: false, hasRoutes: false)

        // Initial launch of daemon if autoStart is true
        let config = configManager.load()
        if config.autoStart {
            let (running, _) = supervisor.isRunning()
            if !running {
                _ = try? supervisor.start(config: config)
            }
        }

        // Start proxies
        forwarder.startConfiguredProxies(config)

        // Build initial menu
        buildMenu()

        // Start background status poller (every 3 seconds)
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.pollStatus()
        }
        pollStatus()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        pollTimer?.invalidate()
        forwarder.stopAll()
    }

    private func pollStatus() {
        let status = client.getStatus()
        let config = configManager.load()

        let wasOnline = currentStatus.isOnline
        currentStatus = status

        // If daemon just came online, auto-reapply serve routes
        if !wasOnline && status.isOnline {
            try? client.reapplyConfiguredServeRoutes(config)
        }

        // Keep proxies active
        forwarder.startConfiguredProxies(config)

        let hasRoutes = !config.serveRoutes.isEmpty || !config.remoteProxies.isEmpty
        updateStatusIcon(isOnline: status.isOnline, hasRoutes: hasRoutes)
        buildMenu()
    }

    private func updateStatusIcon(isOnline: Bool, hasRoutes: Bool) {
        guard let button = statusItem.button else { return }

        // Use standard SF Symbols available in macOS 13+
        let symbolName: String
        if isOnline {
            symbolName = hasRoutes ? "network.badge.shield.half.filled" : "network"
        } else if currentStatus.isProcessRunning {
            symbolName = "network.slash"
        } else {
            symbolName = "xmark.circle"
        }

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Tailscale Userspace") {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = isOnline ? "TS (Online)" : "TS (Offline)"
        }
    }

    private func buildMenu() {
        let menu = NSMenu()
        let config = configManager.load()

        // 1. Header & Status
        let statusText: String
        if currentStatus.isOnline {
            let name = currentStatus.selfName.isEmpty ? "Connected" : currentStatus.selfName
            statusText = "● Tailscale: \(name)"
        } else if currentStatus.backendState == "NeedsLogin" {
            statusText = "▲ Tailscale: Login Required"
        } else if currentStatus.isProcessRunning {
            statusText = "○ Tailscale: Disconnected"
        } else {
            statusText = "✕ Tailscale Daemon: Stopped"
        }
        let statusItem = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        if !currentStatus.tailscaleIPs.isEmpty {
            let ipText = "IP: \(currentStatus.tailscaleIPs.first ?? "")"
            let ipItem = NSMenuItem(title: ipText, action: #selector(copyIP), keyEquivalent: "")
            ipItem.target = self
            ipItem.toolTip = "Click to copy Tailscale IP"
            menu.addItem(ipItem)
        }

        menu.addItem(NSMenuItem.separator())

        // 2. Connect / Disconnect Toggle
        if currentStatus.isOnline {
            let disconnectItem = NSMenuItem(title: "Disconnect", action: #selector(disconnectTailscale), keyEquivalent: "d")
            disconnectItem.target = self
            menu.addItem(disconnectItem)
        } else if currentStatus.backendState == "NeedsLogin", let authURL = currentStatus.authURL, !authURL.isEmpty {
            let loginItem = NSMenuItem(title: "Log In with Browser...", action: #selector(openLoginURL), keyEquivalent: "l")
            loginItem.target = self
            menu.addItem(loginItem)
        } else if currentStatus.isProcessRunning {
            let connectItem = NSMenuItem(title: "Connect", action: #selector(connectTailscale), keyEquivalent: "c")
            connectItem.target = self
            menu.addItem(connectItem)
        } else {
            let startItem = NSMenuItem(title: "Start Userspace Daemon", action: #selector(startDaemon), keyEquivalent: "s")
            startItem.target = self
            menu.addItem(startItem)
        }

        menu.addItem(NSMenuItem.separator())

        // 3. Feature 1: Inbound Tailscale Serve Routes
        let serveSection = NSMenuItem(title: "Inbound Serve (Local ➔ Tailnet)", action: nil, keyEquivalent: "")
        serveSection.isEnabled = false
        menu.addItem(serveSection)

        if config.serveRoutes.isEmpty {
            let emptyItem = NSMenuItem(title: "  (No serve routes configured)", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            let host = currentStatus.selfDNSName.isEmpty ? "your-node.ts.net" : currentStatus.selfDNSName
            for route in config.serveRoutes {
                let statusBadge = route.enabled ? "✓" : "○"
                let title = "  \(statusBadge) localhost:\(route.localPort) ➔ :\(route.servePort)\(route.path)"
                let item = NSMenuItem(title: title, action: #selector(serveRouteClicked(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = route
                item.toolTip = "Click to copy https://\(host):\(route.servePort)\(route.path)"
                menu.addItem(item)
            }
        }

        let addServeItem = NSMenuItem(title: "  [+] Add Serve Route...", action: #selector(promptAddServeRoute), keyEquivalent: "")
        addServeItem.target = self
        menu.addItem(addServeItem)

        menu.addItem(NSMenuItem.separator())

        // 4. Feature 2: Outbound Remote Proxies
        let proxySection = NSMenuItem(title: "Outbound Remote Proxies (Tailnet ➔ Local)", action: nil, keyEquivalent: "")
        proxySection.isEnabled = false
        menu.addItem(proxySection)

        if config.remoteProxies.isEmpty {
            let emptyItem = NSMenuItem(title: "  (No remote proxies configured)", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for proxy in config.remoteProxies {
                let statusBadge = proxy.enabled ? "✓" : "○"
                let title = "  \(statusBadge) localhost:\(proxy.localPort) ➔ \(proxy.remoteHost):\(proxy.remotePort)"
                let item = NSMenuItem(title: title, action: #selector(remoteProxyClicked(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = proxy
                item.toolTip = "Click to open http://localhost:\(proxy.localPort)"
                menu.addItem(item)
            }
        }

        let addProxyItem = NSMenuItem(title: "  [+] Add Remote Proxy...", action: #selector(promptAddRemoteProxy), keyEquivalent: "")
        addProxyItem.target = self
        menu.addItem(addProxyItem)

        menu.addItem(NSMenuItem.separator())

        // 5. Utilities & SOCKS5 Info
        let socksText = "SOCKS5 Proxy: 127.0.0.1:\(config.socks5Port)"
        let socksItem = NSMenuItem(title: socksText, action: #selector(copyProxyEnv), keyEquivalent: "")
        socksItem.target = self
        socksItem.toolTip = "Click to copy shell proxy export variables"
        menu.addItem(socksItem)

        let logsItem = NSMenuItem(title: "Open Logs...", action: #selector(openLogs), keyEquivalent: "")
        logsItem.target = self
        menu.addItem(logsItem)

        menu.addItem(NSMenuItem.separator())

        // 6. Quit
        let quitItem = NSMenuItem(title: "Quit TailUserspace", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        self.statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func copyIP() {
        if let ip = currentStatus.tailscaleIPs.first {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(ip, forType: .string)
        }
    }

    @objc private func connectTailscale() {
        DispatchQueue.global().async { [weak self] in
            try? self?.client.connect()
            DispatchQueue.main.async { self?.pollStatus() }
        }
    }

    @objc private func disconnectTailscale() {
        DispatchQueue.global().async { [weak self] in
            try? self?.client.disconnect()
            DispatchQueue.main.async { self?.pollStatus() }
        }
    }

    @objc private func startDaemon() {
        DispatchQueue.global().async { [weak self] in
            let cfg = self?.configManager.load()
            _ = try? self?.supervisor.start(config: cfg)
            DispatchQueue.main.async { self?.pollStatus() }
        }
    }

    @objc private func openLoginURL() {
        if let urlStr = currentStatus.authURL, let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func copyProxyEnv() {
        let config = configManager.load()
        let env = "export ALL_PROXY=socks5://127.0.0.1:\(config.socks5Port)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(env, forType: .string)
    }

    @objc private func openLogs() {
        let logURL = URL(fileURLWithPath: PathConstants.logFilePath)
        NSWorkspace.shared.open(logURL)
    }

    @objc private func serveRouteClicked(_ sender: NSMenuItem) {
        guard let route = sender.representedObject as? ServeRoute else { return }
        let host = currentStatus.selfDNSName.isEmpty ? "your-node.ts.net" : currentStatus.selfDNSName
        let url = "https://\(host):\(route.servePort)\(route.path)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
    }

    @objc private func remoteProxyClicked(_ sender: NSMenuItem) {
        guard let proxy = sender.representedObject as? RemoteProxy else { return }
        if let url = URL(string: "http://localhost:\(proxy.localPort)") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func promptAddServeRoute() {
        let alert = NSAlert()
        alert.messageText = "Add Inbound Tailscale Serve Route"
        alert.informativeText = "Expose a local service to your tailnet via HTTPS."
        alert.addButton(withTitle: "Add Route")
        alert.addButton(withTitle: "Cancel")

        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 280, height: 60))
        stack.orientation = .vertical
        stack.spacing = 8

        let localField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        localField.placeholderString = "Local Port (e.g. 3000)"

        let serveField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        serveField.placeholderString = "Serve Port (default: 443)"
        serveField.stringValue = "443"

        stack.addArrangedSubview(localField)
        stack.addArrangedSubview(serveField)
        alert.accessoryView = stack

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            if let localPort = Int(localField.stringValue.trimmingCharacters(in: .whitespaces)) {
                let servePort = Int(serveField.stringValue.trimmingCharacters(in: .whitespaces)) ?? 443
                let route = ServeRoute(localPort: localPort, servePort: servePort)
                try? configManager.addServeRoute(route)
                if currentStatus.isOnline {
                    try? client.applyServeRoute(route)
                }
                pollStatus()
            }
        }
    }

    @objc private func promptAddRemoteProxy() {
        let alert = NSAlert()
        alert.messageText = "Add Outbound Remote Proxy"
        alert.informativeText = "Map a remote tailnet host to a local port."
        alert.addButton(withTitle: "Add Proxy")
        alert.addButton(withTitle: "Cancel")

        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 280, height: 60))
        stack.orientation = .vertical
        stack.spacing = 8

        let localField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        localField.placeholderString = "Local Port (e.g. 8080)"

        let remoteField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        remoteField.placeholderString = "Remote Target (e.g. nas.ts.net:80)"

        stack.addArrangedSubview(localField)
        stack.addArrangedSubview(remoteField)
        alert.accessoryView = stack

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let localStr = localField.stringValue.trimmingCharacters(in: .whitespaces)
            let remoteStr = remoteField.stringValue.trimmingCharacters(in: .whitespaces)
            let parts = remoteStr.split(separator: ":")
            if let localPort = Int(localStr), parts.count == 2, let remotePort = Int(parts[1]) {
                let proxy = RemoteProxy(localPort: localPort, remoteHost: String(parts[0]), remotePort: remotePort)
                try? configManager.addRemoteProxy(proxy)
                forwarder.startConfiguredProxies(configManager.load())
                pollStatus()
            }
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
