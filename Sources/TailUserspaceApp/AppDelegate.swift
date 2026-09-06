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
                let scheme = route.proto.lowercased()
                let title = "  \(statusBadge) localhost:\(route.localPort) ➔ \(scheme)://:\(route.servePort)\(route.path)"
                let item = NSMenuItem(title: title, action: #selector(serveRouteClicked(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = route
                item.toolTip = "Click to copy \(scheme)://\(host):\(route.servePort)\(route.path)"
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
            try? self?.client.connect(timeout: 180.0, autoOpenBrowser: true)
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
        let url = "\(route.proto.lowercased())://\(host):\(route.servePort)\(route.path)"
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
        alert.informativeText = "Expose a local service (e.g. 8787 or 3000) to your tailnet via HTTPS or HTTP."
        alert.addButton(withTitle: "Add Route")
        alert.addButton(withTitle: "Cancel")

        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 280, height: 95))
        stack.orientation = .vertical
        stack.spacing = 8

        let protoPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 26), pullsDown: false)
        protoPopup.addItems(withTitles: ["HTTPS (port 443)", "HTTP (port 80)", "HTTP (port 8080)"])

        let localField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        localField.placeholderString = "Local Port (e.g. 8787 or 3000)"

        let serveField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        serveField.placeholderString = "Tailnet Serve Port (default: 443)"
        serveField.stringValue = "443"

        protoPopup.target = nil
        protoPopup.action = nil

        stack.addArrangedSubview(protoPopup)
        stack.addArrangedSubview(localField)
        stack.addArrangedSubview(serveField)
        alert.accessoryView = stack

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            if let localPort = Int(localField.stringValue.trimmingCharacters(in: .whitespaces)) {
                let selectedProto: String
                let defaultPort: Int
                switch protoPopup.indexOfSelectedItem {
                case 1:
                    selectedProto = "http"
                    defaultPort = 80
                case 2:
                    selectedProto = "http"
                    defaultPort = 8080
                default:
                    selectedProto = "https"
                    defaultPort = 443
                }

                let servePort = Int(serveField.stringValue.trimmingCharacters(in: .whitespaces)) ?? defaultPort
                let route = ServeRoute(localPort: localPort, servePort: servePort, proto: selectedProto)
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
        alert.informativeText = "Forward a local port on your Mac to a remote Tailnet node."
        alert.addButton(withTitle: "Add Proxy")
        alert.addButton(withTitle: "Cancel")

        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 300, height: 95))
        stack.orientation = .vertical
        stack.spacing = 8

        let localField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        localField.placeholderString = "Local Port to Listen On (e.g. 9999 or 8080)"

        let remoteHostField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        remoteHostField.placeholderString = "Remote Host / IP (e.g. node.ts.net)"

        let remotePortField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        remotePortField.placeholderString = "Remote Target Port (default: 80)"
        remotePortField.stringValue = "80"

        stack.addArrangedSubview(localField)
        stack.addArrangedSubview(remoteHostField)
        stack.addArrangedSubview(remotePortField)
        alert.accessoryView = stack

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let localStr = localField.stringValue.trimmingCharacters(in: .whitespaces)
            var remoteHostStr = remoteHostField.stringValue.trimmingCharacters(in: .whitespaces)
            let remotePortStr = remotePortField.stringValue.trimmingCharacters(in: .whitespaces)

            guard let localPort = Int(localStr), (1...65535).contains(localPort) else {
                showErrorAlert(title: "Invalid Local Port", message: "Please enter a valid local port number between 1 and 65535.")
                return
            }

            guard !remoteHostStr.isEmpty else {
                showErrorAlert(title: "Missing Remote Host", message: "Please enter a remote Tailnet hostname or IP address.")
                return
            }

            var remotePort = Int(remotePortStr) ?? 80
            // If user typed host:port in the remote host field, parse it out automatically
            if remoteHostStr.contains(":") {
                let parts = remoteHostStr.split(separator: ":")
                if parts.count == 2, let parsedPort = Int(parts[1]) {
                    remoteHostStr = String(parts[0])
                    remotePort = parsedPort
                }
            }

            guard (1...65535).contains(remotePort) else {
                showErrorAlert(title: "Invalid Remote Port", message: "Please enter a valid target port between 1 and 65535.")
                return
            }

            let proxy = RemoteProxy(localPort: localPort, remoteHost: remoteHostStr, remotePort: remotePort)
            do {
                try configManager.addRemoteProxy(proxy)
                let config = configManager.load()
                forwarder.startConfiguredProxies(config)
                pollStatus()
            } catch {
                showErrorAlert(title: "Failed to Add Proxy", message: error.localizedDescription)
            }
        }
    }

    private func showErrorAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
