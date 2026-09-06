import Cocoa
import TailUserspaceCore

public final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
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
            self?.pollStatus(forceReloadConfig: false)
        }
        pollStatus(forceReloadConfig: true)
    }

    public func applicationWillTerminate(_ notification: Notification) {
        pollTimer?.invalidate()
        forwarder.stopAll()
    }

    // MARK: - NSMenuDelegate (Instant Sync on Menu Open)

    public func menuWillOpen(_ menu: NSMenu) {
        // Immediately reload config and refresh status when user clicks menubar item
        pollStatus(forceReloadConfig: true)
    }

    private func pollStatus(forceReloadConfig: Bool = false) {
        let status = client.getStatus()
        let config = configManager.load(forceReload: forceReloadConfig)

        let wasOnline = currentStatus.isOnline
        currentStatus = status

        // If daemon just came online, auto-reapply serve routes
        if !wasOnline && status.isOnline {
            try? client.reapplyConfiguredServeRoutes(config)
        }

        // Keep proxies active and synchronized with config changes
        forwarder.startConfiguredProxies(config)

        let hasRoutes = !config.serveRoutes.isEmpty || !config.remoteProxies.isEmpty
        updateStatusIcon(isOnline: status.isOnline, hasRoutes: hasRoutes)
        buildMenu()
    }

    private func updateStatusIcon(isOnline: Bool, hasRoutes: Bool) {
        guard let button = statusItem.button else { return }

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

    // MARK: - Menu Construction

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        let config = configManager.load()

        // 1. Status & Identity Group
        buildHeaderSection(menu: menu)

        menu.addItem(NSMenuItem.separator())

        // 2. Connection Lifecycle Group
        buildConnectionControls(menu: menu)

        menu.addItem(NSMenuItem.separator())

        // 3. Inbound Serve Routes (Local ➔ Tailnet)
        buildServeSection(menu: menu, config: config)

        menu.addItem(NSMenuItem.separator())

        // 4. Outbound Remote Proxies (Tailnet ➔ Local)
        buildProxySection(menu: menu, config: config)

        menu.addItem(NSMenuItem.separator())

        // 5. Proxy & Environment Quick Access
        buildProxyEnvSection(menu: menu, config: config)

        menu.addItem(NSMenuItem.separator())

        // 6. Configuration & Diagnostics
        buildConfigSection(menu: menu)

        menu.addItem(NSMenuItem.separator())

        // 7. Footer & Quit
        buildFooterSection(menu: menu)

        self.statusItem.menu = menu
    }

    // MARK: - Section Builders

    private func buildHeaderSection(menu: NSMenu) {
        let statusTitle: String
        let statusImageName: String

        if currentStatus.isOnline {
            let name = currentStatus.selfName.isEmpty ? "Connected" : currentStatus.selfName
            statusTitle = "● Tailscale: \(name)"
            statusImageName = "checkmark.circle.fill"
        } else if currentStatus.backendState == "NeedsLogin" {
            statusTitle = "▲ Tailscale: Login Required"
            statusImageName = "exclamationmark.triangle.fill"
        } else if currentStatus.isProcessRunning {
            statusTitle = "○ Tailscale: Disconnected"
            statusImageName = "circle.slash"
        } else {
            statusTitle = "✕ Tailscale Daemon: Stopped"
            statusImageName = "xmark.circle"
        }

        let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        if let img = NSImage(systemSymbolName: statusImageName, accessibilityDescription: statusTitle) {
            img.isTemplate = true
            statusItem.image = img
        }
        menu.addItem(statusItem)

        if let ip = currentStatus.tailscaleIPs.first, !ip.isEmpty {
            let ipItem = makeMenuItem(
                title: "IP: \(ip)",
                action: #selector(copyIP),
                systemImage: "doc.on.doc",
                toolTip: "Click to copy Tailscale IP to clipboard"
            )
            menu.addItem(ipItem)
        }

        if !currentStatus.selfDNSName.isEmpty {
            let domainItem = makeMenuItem(
                title: "Domain: \(currentStatus.selfDNSName)",
                action: #selector(copyDomain),
                systemImage: "globe",
                toolTip: "Click to copy Tailnet domain to clipboard"
            )
            menu.addItem(domainItem)
        }
    }

    private func buildConnectionControls(menu: NSMenu) {
        if currentStatus.isOnline {
            let disconnectItem = makeMenuItem(
                title: "Disconnect",
                action: #selector(disconnectTailscale),
                keyEquivalent: "d",
                systemImage: "power"
            )
            menu.addItem(disconnectItem)

            let reauthItem = makeMenuItem(
                title: "Re-authenticate...",
                action: #selector(reauthTailscale),
                systemImage: "arrow.triangle.2.circlepath"
            )
            menu.addItem(reauthItem)
        } else if currentStatus.backendState == "NeedsLogin", let authURL = currentStatus.authURL, !authURL.isEmpty {
            let loginItem = makeMenuItem(
                title: "Log In with Browser...",
                action: #selector(openLoginURL),
                keyEquivalent: "l",
                systemImage: "safari"
            )
            menu.addItem(loginItem)
        } else if currentStatus.isProcessRunning {
            let connectItem = makeMenuItem(
                title: "Connect",
                action: #selector(connectTailscale),
                keyEquivalent: "c",
                systemImage: "bolt.fill"
            )
            menu.addItem(connectItem)
        } else {
            let startItem = makeMenuItem(
                title: "Start Userspace Daemon",
                action: #selector(startDaemon),
                keyEquivalent: "s",
                systemImage: "play.fill"
            )
            menu.addItem(startItem)
        }
    }

    private func buildServeSection(menu: NSMenu, config: TailUserspaceConfig) {
        menu.addItem(makeSectionHeader(title: "Inbound Serve (Local ➔ Tailnet)"))

        if config.serveRoutes.isEmpty {
            let emptyItem = NSMenuItem(title: "  (No serve routes configured)", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            let host = currentStatus.selfDNSName.isEmpty ? "your-node.ts.net" : currentStatus.selfDNSName
            for route in config.serveRoutes {
                let dot = route.enabled ? "●" : "○"
                let scheme = route.proto.lowercased()
                let title = "  \(dot) localhost:\(route.localPort) ➔ \(scheme)://:\(route.servePort)\(route.path)"

                let routeItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                let sub = NSMenu()

                let header = NSMenuItem(title: "Serve: localhost:\(route.localPort)", action: nil, keyEquivalent: "")
                header.isEnabled = false
                sub.addItem(header)

                let toggleTitle = route.enabled ? "Active (Click to Pause)" : "Paused (Click to Enable)"
                let toggleItem = makeMenuItem(
                    title: toggleTitle,
                    action: #selector(toggleServeRouteClicked(_:)),
                    systemImage: route.enabled ? "checkmark.circle" : "pause.circle"
                )
                toggleItem.representedObject = route
                sub.addItem(toggleItem)

                sub.addItem(NSMenuItem.separator())

                let openItem = makeMenuItem(
                    title: "Open in Browser",
                    action: #selector(openServeRouteInBrowser(_:)),
                    systemImage: "arrow.up.right.square"
                )
                openItem.representedObject = route
                sub.addItem(openItem)

                let copyTailnetItem = makeMenuItem(
                    title: "Copy Tailnet URL",
                    action: #selector(copyServeRouteURL(_:)),
                    systemImage: "doc.on.doc"
                )
                copyTailnetItem.representedObject = route
                copyTailnetItem.toolTip = "\(scheme)://\(host):\(route.servePort)\(route.path)"
                sub.addItem(copyTailnetItem)

                let copyLocalItem = makeMenuItem(
                    title: "Copy Local URL",
                    action: #selector(copyServeRouteLocalURL(_:)),
                    systemImage: "doc.on.doc"
                )
                copyLocalItem.representedObject = route
                copyLocalItem.toolTip = "http://localhost:\(route.localPort)"
                sub.addItem(copyLocalItem)

                sub.addItem(NSMenuItem.separator())

                let editItem = makeMenuItem(
                    title: "Edit Route...",
                    action: #selector(editServeRouteClicked(_:)),
                    systemImage: "pencil"
                )
                editItem.representedObject = route
                sub.addItem(editItem)

                let deleteItem = makeMenuItem(
                    title: "Delete Route...",
                    action: #selector(deleteServeRouteClicked(_:)),
                    systemImage: "trash"
                )
                deleteItem.representedObject = route
                sub.addItem(deleteItem)

                routeItem.submenu = sub
                menu.addItem(routeItem)
            }
        }

        let addServeItem = makeMenuItem(
            title: "  [+] Add Serve Route...",
            action: #selector(promptAddServeRoute),
            systemImage: "plus"
        )
        menu.addItem(addServeItem)
    }

    private func buildProxySection(menu: NSMenu, config: TailUserspaceConfig) {
        menu.addItem(makeSectionHeader(title: "Outbound Remote Proxies (Tailnet ➔ Local)"))

        if config.remoteProxies.isEmpty {
            let emptyItem = NSMenuItem(title: "  (No remote proxies configured)", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for proxy in config.remoteProxies {
                let dot = proxy.enabled ? "●" : "○"
                let tlsTag = proxy.terminateTLS ? " [TLS]" : ""
                let title = "  \(dot) localhost:\(proxy.localPort) ➔ \(proxy.remoteHost):\(proxy.remotePort)\(tlsTag)"

                let proxyItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                let sub = NSMenu()

                let header = NSMenuItem(title: "Proxy: localhost:\(proxy.localPort)\(tlsTag)", action: nil, keyEquivalent: "")
                header.isEnabled = false
                sub.addItem(header)

                let toggleTitle = proxy.enabled ? "Active (Click to Pause)" : "Paused (Click to Activate)"
                let toggleItem = makeMenuItem(
                    title: toggleTitle,
                    action: #selector(toggleRemoteProxyClicked(_:)),
                    systemImage: proxy.enabled ? "checkmark.circle" : "pause.circle"
                )
                toggleItem.representedObject = proxy
                sub.addItem(toggleItem)

                sub.addItem(NSMenuItem.separator())

                let openItem = makeMenuItem(
                    title: "Open Local Endpoint",
                    action: #selector(openRemoteProxyInBrowser(_:)),
                    systemImage: "arrow.up.right.square"
                )
                openItem.representedObject = proxy
                sub.addItem(openItem)

                let copyLocalItem = makeMenuItem(
                    title: "Copy Local URL",
                    action: #selector(copyRemoteProxyLocalURL(_:)),
                    systemImage: "doc.on.doc"
                )
                copyLocalItem.representedObject = proxy
                copyLocalItem.toolTip = "http://localhost:\(proxy.localPort)"
                sub.addItem(copyLocalItem)

                let copyTargetItem = makeMenuItem(
                    title: "Copy Target Endpoint",
                    action: #selector(copyRemoteProxyTargetURL(_:)),
                    systemImage: "doc.on.doc"
                )
                copyTargetItem.representedObject = proxy
                copyTargetItem.toolTip = "\(proxy.remoteHost):\(proxy.remotePort)"
                sub.addItem(copyTargetItem)

                sub.addItem(NSMenuItem.separator())

                let editItem = makeMenuItem(
                    title: "Edit Proxy...",
                    action: #selector(editRemoteProxyClicked(_:)),
                    systemImage: "pencil"
                )
                editItem.representedObject = proxy
                sub.addItem(editItem)

                let deleteItem = makeMenuItem(
                    title: "Delete Proxy...",
                    action: #selector(deleteRemoteProxyClicked(_:)),
                    systemImage: "trash"
                )
                deleteItem.representedObject = proxy
                sub.addItem(deleteItem)

                proxyItem.submenu = sub
                menu.addItem(proxyItem)
            }
        }

        let addProxyItem = makeMenuItem(
            title: "  [+] Add Outbound Proxy...",
            action: #selector(promptAddRemoteProxy),
            systemImage: "plus"
        )
        menu.addItem(addProxyItem)
    }

    private func buildProxyEnvSection(menu: NSMenu, config: TailUserspaceConfig) {
        menu.addItem(makeSectionHeader(title: "Userspace Proxies & Shell Environment"))

        let socksText = "SOCKS5 Proxy: 127.0.0.1:\(config.socks5Port)"
        let socksItem = makeMenuItem(
            title: socksText,
            action: #selector(copySocks5Address),
            systemImage: "network",
            toolTip: "Click to copy 127.0.0.1:\(config.socks5Port)"
        )
        menu.addItem(socksItem)

        let httpText = "HTTP Proxy: 127.0.0.1:\(config.httpProxyPort)"
        let httpItem = makeMenuItem(
            title: httpText,
            action: #selector(copyHttpAddress),
            systemImage: "network",
            toolTip: "Click to copy 127.0.0.1:\(config.httpProxyPort)"
        )
        menu.addItem(httpItem)

        let envItem = makeMenuItem(
            title: "Copy Shell Export (ALL_PROXY)",
            action: #selector(copyProxyEnv),
            systemImage: "terminal",
            toolTip: "Click to copy 'export ALL_PROXY=socks5://127.0.0.1:\(config.socks5Port)'"
        )
        menu.addItem(envItem)
    }

    private func buildConfigSection(menu: NSMenu) {
        menu.addItem(makeSectionHeader(title: "Configuration & Diagnostics"))

        let openConfigItem = makeMenuItem(
            title: "Open Configuration File (config.json)",
            action: #selector(openConfigFile),
            systemImage: "doc.text",
            toolTip: "Open ~/.local/share/tail-userspace/config.json in default editor"
        )
        menu.addItem(openConfigItem)

        let viewConfigItem = makeMenuItem(
            title: "View Configuration in App...",
            action: #selector(viewConfigInApp),
            systemImage: "eye",
            toolTip: "Inspect current JSON configuration"
        )
        menu.addItem(viewConfigItem)

        let revealItem = makeMenuItem(
            title: "Reveal Data Directory in Finder",
            action: #selector(revealDirectoryInFinder),
            systemImage: "folder"
        )
        menu.addItem(revealItem)

        let logsItem = makeMenuItem(
            title: "View Daemon Logs (tailscaled.log)",
            action: #selector(openLogs),
            systemImage: "list.bullet.rectangle"
        )
        menu.addItem(logsItem)

        let resetServeItem = makeMenuItem(
            title: "Reset Tailscale Serve...",
            action: #selector(resetServeClicked),
            systemImage: "arrow.counterclockwise"
        )
        menu.addItem(resetServeItem)
    }

    private func buildFooterSection(menu: NSMenu) {
        let versionItem = NSMenuItem(title: "Tailscale Userspace v1.0 (Darwin)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        let quitItem = makeMenuItem(
            title: "Quit TailUserspace",
            action: #selector(quitApp),
            keyEquivalent: "q",
            systemImage: "power"
        )
        menu.addItem(quitItem)
    }

    // MARK: - UI Helpers

    private func makeMenuItem(
        title: String,
        action: Selector?,
        keyEquivalent: String = "",
        systemImage: String? = nil,
        toolTip: String? = nil,
        isEnabled: Bool = true
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.isEnabled = isEnabled
        if let toolTip = toolTip {
            item.toolTip = toolTip
        }
        if let sysName = systemImage, let img = NSImage(systemSymbolName: sysName, accessibilityDescription: title) {
            img.isTemplate = true
            item.image = img
        }
        return item
    }

    private func makeSectionHeader(title: String) -> NSMenuItem {
        let item = NSMenuItem()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        item.attributedTitle = NSAttributedString(string: title.uppercased(), attributes: attributes)
        item.isEnabled = false
        return item
    }

    // MARK: - Copy Actions

    @objc private func copyIP() {
        if let ip = currentStatus.tailscaleIPs.first {
            copyToClipboard(ip)
        }
    }

    @objc private func copyDomain() {
        if !currentStatus.selfDNSName.isEmpty {
            copyToClipboard(currentStatus.selfDNSName)
        }
    }

    @objc private func copySocks5Address() {
        let config = configManager.load()
        copyToClipboard("127.0.0.1:\(config.socks5Port)")
    }

    @objc private func copyHttpAddress() {
        let config = configManager.load()
        copyToClipboard("127.0.0.1:\(config.httpProxyPort)")
    }

    @objc private func copyProxyEnv() {
        let config = configManager.load()
        copyToClipboard("export ALL_PROXY=socks5://127.0.0.1:\(config.socks5Port)")
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Connection Actions

    @objc private func connectTailscale() {
        DispatchQueue.global().async { [weak self] in
            try? self?.client.connect(timeout: 180.0, autoOpenBrowser: true)
            DispatchQueue.main.async { self?.pollStatus(forceReloadConfig: true) }
        }
    }

    @objc private func disconnectTailscale() {
        DispatchQueue.global().async { [weak self] in
            try? self?.client.disconnect()
            DispatchQueue.main.async { self?.pollStatus(forceReloadConfig: true) }
        }
    }

    @objc private func reauthTailscale() {
        DispatchQueue.global().async { [weak self] in
            try? self?.client.connect(extraArgs: ["--force-reauth"], timeout: 180.0, autoOpenBrowser: true)
            DispatchQueue.main.async { self?.pollStatus(forceReloadConfig: true) }
        }
    }

    @objc private func startDaemon() {
        DispatchQueue.global().async { [weak self] in
            let cfg = self?.configManager.load(forceReload: true)
            _ = try? self?.supervisor.start(config: cfg)
            DispatchQueue.main.async { self?.pollStatus(forceReloadConfig: true) }
        }
    }

    @objc private func openLoginURL() {
        if let urlStr = currentStatus.authURL, let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Inbound Serve Route Actions

    @objc private func toggleServeRouteClicked(_ sender: NSMenuItem) {
        guard let route = sender.representedObject as? ServeRoute else { return }
        try? configManager.toggleServeRoute(id: route.id)
        let config = configManager.load(forceReload: true)
        if currentStatus.isOnline {
            try? client.reapplyConfiguredServeRoutes(config)
        }
        pollStatus(forceReloadConfig: true)
    }

    @objc private func openServeRouteInBrowser(_ sender: NSMenuItem) {
        guard let route = sender.representedObject as? ServeRoute else { return }
        let host = currentStatus.selfDNSName.isEmpty ? "your-node.ts.net" : currentStatus.selfDNSName
        let urlStr = "\(route.proto.lowercased())://\(host):\(route.servePort)\(route.path)"
        if let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func copyServeRouteURL(_ sender: NSMenuItem) {
        guard let route = sender.representedObject as? ServeRoute else { return }
        let host = currentStatus.selfDNSName.isEmpty ? "your-node.ts.net" : currentStatus.selfDNSName
        let url = "\(route.proto.lowercased())://\(host):\(route.servePort)\(route.path)"
        copyToClipboard(url)
    }

    @objc private func copyServeRouteLocalURL(_ sender: NSMenuItem) {
        guard let route = sender.representedObject as? ServeRoute else { return }
        copyToClipboard("http://localhost:\(route.localPort)")
    }

    @objc private func editServeRouteClicked(_ sender: NSMenuItem) {
        guard let route = sender.representedObject as? ServeRoute else { return }

        let alert = NSAlert()
        alert.messageText = "Edit Inbound Serve Route"
        alert.informativeText = "Modify route settings for localhost:\(route.localPort)."
        alert.addButton(withTitle: "Save Changes")
        alert.addButton(withTitle: "Cancel")

        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))
        stack.orientation = .vertical
        stack.spacing = 8

        let protoPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 26), pullsDown: false)
        protoPopup.addItems(withTitles: ["HTTPS (port 443)", "HTTP (port 80)", "HTTP (port 8080)", "Custom TCP"])
        if route.proto == "https" {
            protoPopup.selectItem(at: 0)
        } else if route.proto == "http" && route.servePort == 80 {
            protoPopup.selectItem(at: 1)
        } else if route.proto == "http" && route.servePort == 8080 {
            protoPopup.selectItem(at: 2)
        } else {
            protoPopup.selectItem(at: 3)
        }

        let localField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        localField.placeholderString = "Local Port (e.g. 3000)"
        localField.stringValue = "\(route.localPort)"

        let serveField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        serveField.placeholderString = "Tailnet Serve Port"
        serveField.stringValue = "\(route.servePort)"

        let pathField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        pathField.placeholderString = "Path Prefix (default: /)"
        pathField.stringValue = route.path

        let enabledCheckbox = NSButton(checkboxWithTitle: "Route is active/enabled", target: nil, action: nil)
        enabledCheckbox.state = route.enabled ? .on : .off

        stack.addArrangedSubview(protoPopup)
        stack.addArrangedSubview(localField)
        stack.addArrangedSubview(serveField)
        stack.addArrangedSubview(pathField)
        stack.addArrangedSubview(enabledCheckbox)
        alert.accessoryView = stack

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            guard let localPort = Int(localField.stringValue.trimmingCharacters(in: .whitespaces)), (1...65535).contains(localPort) else {
                showErrorAlert(title: "Invalid Local Port", message: "Port must be a number between 1 and 65535.")
                return
            }
            guard let servePort = Int(serveField.stringValue.trimmingCharacters(in: .whitespaces)), (1...65535).contains(servePort) else {
                showErrorAlert(title: "Invalid Serve Port", message: "Port must be a number between 1 and 65535.")
                return
            }
            let proto: String
            switch protoPopup.indexOfSelectedItem {
            case 0: proto = "https"
            case 1, 2: proto = "http"
            default: proto = "tcp"
            }
            var path = pathField.stringValue.trimmingCharacters(in: .whitespaces)
            if path.isEmpty { path = "/" }
            if !path.hasPrefix("/") { path = "/" + path }

            let updated = ServeRoute(
                id: route.id,
                localPort: localPort,
                servePort: servePort,
                proto: proto,
                path: path,
                enabled: enabledCheckbox.state == .on
            )

            do {
                try configManager.updateServeRoute(id: route.id, updatedRoute: updated)
                if currentStatus.isOnline {
                    try? client.reapplyConfiguredServeRoutes(configManager.load(forceReload: true))
                }
                pollStatus(forceReloadConfig: true)
            } catch {
                showErrorAlert(title: "Failed to Update Route", message: error.localizedDescription)
            }
        }
    }

    @objc private func deleteServeRouteClicked(_ sender: NSMenuItem) {
        guard let route = sender.representedObject as? ServeRoute else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete Inbound Serve Route?"
        alert.informativeText = "Are you sure you want to delete the serve route for localhost:\(route.localPort) (➔ \(route.proto)://:\(route.servePort)\(route.path))?"
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            try? configManager.removeServeRoute(id: route.id)
            if currentStatus.isOnline {
                try? client.resetServe()
                try? client.reapplyConfiguredServeRoutes(configManager.load(forceReload: true))
            }
            pollStatus(forceReloadConfig: true)
        }
    }

    @objc private func promptAddServeRoute() {
        let alert = NSAlert()
        alert.messageText = "Add Inbound Tailscale Serve Route"
        alert.informativeText = "Expose a local service (e.g. 8787 or 3000) to your tailnet via HTTPS or HTTP."
        alert.addButton(withTitle: "Add Route")
        alert.addButton(withTitle: "Cancel")

        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 320, height: 95))
        stack.orientation = .vertical
        stack.spacing = 8

        let protoPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 26), pullsDown: false)
        protoPopup.addItems(withTitles: ["HTTPS (port 443)", "HTTP (port 80)", "HTTP (port 8080)"])

        let localField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        localField.placeholderString = "Local Port (e.g. 8787 or 3000)"

        let serveField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        serveField.placeholderString = "Tailnet Serve Port (default: 443)"
        serveField.stringValue = "443"

        stack.addArrangedSubview(protoPopup)
        stack.addArrangedSubview(localField)
        stack.addArrangedSubview(serveField)
        alert.accessoryView = stack

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            if let localPort = Int(localField.stringValue.trimmingCharacters(in: .whitespaces)), (1...65535).contains(localPort) {
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
                pollStatus(forceReloadConfig: true)
            } else {
                showErrorAlert(title: "Invalid Local Port", message: "Please enter a valid local port number between 1 and 65535.")
            }
        }
    }

    @objc private func resetServeClicked() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Reset Tailscale Serve Configuration?"
        alert.informativeText = "This resets active serve endpoints on the daemon. Configured routes can be re-applied at any time."
        alert.addButton(withTitle: "Reset Serve")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            try? client.resetServe()
            pollStatus(forceReloadConfig: true)
        }
    }

    // MARK: - Outbound Remote Proxy Actions

    @objc private func toggleRemoteProxyClicked(_ sender: NSMenuItem) {
        guard let proxy = sender.representedObject as? RemoteProxy else { return }
        try? configManager.toggleRemoteProxy(id: proxy.id)
        let config = configManager.load(forceReload: true)
        forwarder.startConfiguredProxies(config)
        pollStatus(forceReloadConfig: true)
    }

    @objc private func openRemoteProxyInBrowser(_ sender: NSMenuItem) {
        guard let proxy = sender.representedObject as? RemoteProxy else { return }
        if let url = URL(string: "http://localhost:\(proxy.localPort)") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func copyRemoteProxyLocalURL(_ sender: NSMenuItem) {
        guard let proxy = sender.representedObject as? RemoteProxy else { return }
        copyToClipboard("http://localhost:\(proxy.localPort)")
    }

    @objc private func copyRemoteProxyTargetURL(_ sender: NSMenuItem) {
        guard let proxy = sender.representedObject as? RemoteProxy else { return }
        copyToClipboard("\(proxy.remoteHost):\(proxy.remotePort)")
    }

    @objc private func editRemoteProxyClicked(_ sender: NSMenuItem) {
        guard let proxy = sender.representedObject as? RemoteProxy else { return }

        let alert = NSAlert()
        alert.messageText = "Edit Outbound Remote Proxy"
        alert.informativeText = "Modify proxy configuration for localhost:\(proxy.localPort)."
        alert.addButton(withTitle: "Save Changes")
        alert.addButton(withTitle: "Cancel")

        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 330, height: 145))
        stack.orientation = .vertical
        stack.spacing = 8

        let localField = NSTextField(frame: NSRect(x: 0, y: 0, width: 330, height: 24))
        localField.placeholderString = "Local Port to Listen On (e.g. 9999)"
        localField.stringValue = "\(proxy.localPort)"

        let remoteHostField = NSTextField(frame: NSRect(x: 0, y: 0, width: 330, height: 24))
        remoteHostField.placeholderString = "Remote Host / IP (e.g. node.ts.net)"
        remoteHostField.stringValue = proxy.remoteHost

        let remotePortField = NSTextField(frame: NSRect(x: 0, y: 0, width: 330, height: 24))
        remotePortField.placeholderString = "Remote Target Port"
        remotePortField.stringValue = "\(proxy.remotePort)"

        let tlsCheckbox = NSButton(checkboxWithTitle: "Terminate remote TLS (upstream HTTPS -> local HTTP)", target: nil, action: nil)
        tlsCheckbox.state = proxy.terminateTLS ? .on : .off

        let enabledCheckbox = NSButton(checkboxWithTitle: "Proxy is active/enabled", target: nil, action: nil)
        enabledCheckbox.state = proxy.enabled ? .on : .off

        stack.addArrangedSubview(localField)
        stack.addArrangedSubview(remoteHostField)
        stack.addArrangedSubview(remotePortField)
        stack.addArrangedSubview(tlsCheckbox)
        stack.addArrangedSubview(enabledCheckbox)
        alert.accessoryView = stack

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let localStr = localField.stringValue.trimmingCharacters(in: .whitespaces)
            var remoteHostStr = remoteHostField.stringValue.trimmingCharacters(in: .whitespaces)
            let remotePortStr = remotePortField.stringValue.trimmingCharacters(in: .whitespaces)

            guard let localPort = Int(localStr), (1...65535).contains(localPort) else {
                showErrorAlert(title: "Invalid Local Port", message: "Please enter a valid local port between 1 and 65535.")
                return
            }

            guard !remoteHostStr.isEmpty else {
                showErrorAlert(title: "Missing Remote Host", message: "Please enter a remote hostname or IP.")
                return
            }

            var remotePort = Int(remotePortStr) ?? 80
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

            let updated = RemoteProxy(
                id: proxy.id,
                localPort: localPort,
                remoteHost: remoteHostStr,
                remotePort: remotePort,
                terminateTLS: tlsCheckbox.state == .on,
                enabled: enabledCheckbox.state == .on
            )

            do {
                try configManager.updateRemoteProxy(id: proxy.id, updatedProxy: updated)
                let cfg = configManager.load(forceReload: true)
                forwarder.startConfiguredProxies(cfg)
                pollStatus(forceReloadConfig: true)
            } catch {
                showErrorAlert(title: "Failed to Update Proxy", message: error.localizedDescription)
            }
        }
    }

    @objc private func deleteRemoteProxyClicked(_ sender: NSMenuItem) {
        guard let proxy = sender.representedObject as? RemoteProxy else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete Outbound Remote Proxy?"
        alert.informativeText = "Are you sure you want to delete the proxy for localhost:\(proxy.localPort) (➔ \(proxy.remoteHost):\(proxy.remotePort))?"
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            try? configManager.removeRemoteProxy(id: proxy.id)
            let cfg = configManager.load(forceReload: true)
            forwarder.startConfiguredProxies(cfg)
            pollStatus(forceReloadConfig: true)
        }
    }

    @objc private func promptAddRemoteProxy() {
        let alert = NSAlert()
        alert.messageText = "Add Outbound Remote Proxy"
        alert.informativeText = "Forward a local port on your Mac to a remote Tailnet node."
        alert.addButton(withTitle: "Add Proxy")
        alert.addButton(withTitle: "Cancel")

        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 320, height: 125))
        stack.orientation = .vertical
        stack.spacing = 8

        let localField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        localField.placeholderString = "Local Port to Listen On (e.g. 9999 or 8080)"

        let remoteHostField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        remoteHostField.placeholderString = "Remote Host / IP (e.g. node.ts.net)"

        let remotePortField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        remotePortField.placeholderString = "Remote Target Port (default: 80)"
        remotePortField.stringValue = "80"

        let tlsCheckbox = NSButton(checkboxWithTitle: "Terminate remote TLS (upstream HTTPS -> local HTTP)", target: nil, action: nil)
        tlsCheckbox.state = .off

        stack.addArrangedSubview(localField)
        stack.addArrangedSubview(remoteHostField)
        stack.addArrangedSubview(remotePortField)
        stack.addArrangedSubview(tlsCheckbox)
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

            let terminateTLS = (tlsCheckbox.state == .on)
            let proxy = RemoteProxy(localPort: localPort, remoteHost: remoteHostStr, remotePort: remotePort, terminateTLS: terminateTLS)
            do {
                try configManager.addRemoteProxy(proxy)
                let config = configManager.load(forceReload: true)
                forwarder.startConfiguredProxies(config)
                pollStatus(forceReloadConfig: true)
            } catch {
                showErrorAlert(title: "Failed to Add Proxy", message: error.localizedDescription)
            }
        }
    }

    // MARK: - Configuration & Files

    @objc private func openConfigFile() {
        try? PathConstants.ensureDirectoriesExist()
        let configURL = PathConstants.configURL
        if !FileManager.default.fileExists(atPath: configURL.path) {
            _ = try? configManager.save(configManager.load())
        }
        NSWorkspace.shared.open(configURL)
    }

    @objc private func viewConfigInApp() {
        let configPath = PathConstants.configPath
        guard let rawData = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let jsonString = String(data: rawData, encoding: .utf8) else {
            showErrorAlert(title: "Configuration File Not Found", message: "No configuration file found at \(configPath).")
            return
        }

        let alert = NSAlert()
        alert.messageText = "Tailscale Userspace Configuration"
        alert.informativeText = "Location: \(configPath)"
        alert.addButton(withTitle: "Close")
        alert.addButton(withTitle: "Copy JSON")
        alert.addButton(withTitle: "Open in External Editor")

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: 300))
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 300))
        textView.string = jsonString
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.autoresizingMask = [.width, .height]
        scrollView.documentView = textView

        alert.accessoryView = scrollView

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            copyToClipboard(jsonString)
        } else if response == .alertThirdButtonReturn {
            openConfigFile()
        }
    }

    @objc private func revealDirectoryInFinder() {
        try? PathConstants.ensureDirectoriesExist()
        let configURL = PathConstants.configURL
        if !FileManager.default.fileExists(atPath: configURL.path) {
            _ = try? configManager.save(configManager.load())
        }
        NSWorkspace.shared.activateFileViewerSelecting([configURL])
    }

    @objc private func openLogs() {
        try? PathConstants.ensureDirectoriesExist()
        let logURL = PathConstants.logFileURL
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: "".data(using: .utf8), attributes: nil)
        }
        NSWorkspace.shared.open(logURL)
    }

    // MARK: - Utilities & Quit

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
