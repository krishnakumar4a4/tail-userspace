import Foundation
import TailUserspaceCore

var passed = 0
var failed = 0

func assertTest(_ condition: Bool, _ name: String) {
    if condition {
        print("  ✓ \(name)")
        passed += 1
    } else {
        print("  ✗ FAIL: \(name)")
        failed += 1
    }
}

print("Running TailUserspaceCore Tests...")

// Test 1: PathConstants with custom environment
do {
    let uniqueID = UUID().uuidString
    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tail_test_\(uniqueID)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    setenv("TAIL_USERSPACE_DIR", tempDir.path, 1)

    assertTest(PathConstants.baseDirectory.path == tempDir.path, "PathConstants baseDirectory matches custom env")
    assertTest(PathConstants.socketPath == tempDir.appendingPathComponent("tailscaled.sock").path, "PathConstants socketPath matches custom env")
    assertTest(PathConstants.statePath == tempDir.appendingPathComponent("tailscaled.state").path, "PathConstants statePath matches custom env")
    assertTest(PathConstants.configPath == tempDir.appendingPathComponent("config.json").path, "PathConstants configPath matches custom env")

    unsetenv("TAIL_USERSPACE_DIR")
    try? FileManager.default.removeItem(at: tempDir)
} catch {
    print("Test 1 error: \(error)")
    failed += 1
}

// Test 2: ConfigManager ServeRoutes
do {
    let uniqueID = UUID().uuidString
    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tail_test_\(uniqueID)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    setenv("TAIL_USERSPACE_DIR", tempDir.path, 1)

    let manager = ConfigManager()
    let initial = manager.load()
    assertTest(initial.serveRoutes.isEmpty, "Initial config has no serve routes")

    let route = ServeRoute(localPort: 3000, servePort: 443, proto: "https", path: "/api")
    try manager.addServeRoute(route)

    let loaded = manager.load()
    assertTest(loaded.serveRoutes.count == 1, "ServeRoute added successfully")
    assertTest(loaded.serveRoutes.first?.localPort == 3000, "ServeRoute localPort matches")
    assertTest(loaded.serveRoutes.first?.servePort == 443, "ServeRoute servePort matches")
    assertTest(loaded.serveRoutes.first?.enabled == true, "ServeRoute is enabled by default")

    try manager.toggleServeRoute(id: route.id)
    assertTest(manager.load().serveRoutes.first?.enabled == false, "ServeRoute toggle disables it")

    let updatedRoute = ServeRoute(id: route.id, localPort: 3001, servePort: 8443, proto: "https", path: "/v2", enabled: true)
    try manager.updateServeRoute(id: route.id, updatedRoute: updatedRoute)
    let reloadedRoute = manager.load().serveRoutes.first
    assertTest(reloadedRoute?.localPort == 3001, "ServeRoute updated localPort matches 3001")
    assertTest(reloadedRoute?.servePort == 8443, "ServeRoute updated servePort matches 8443")
    assertTest(reloadedRoute?.path == "/v2", "ServeRoute updated path matches /v2")

    try manager.removeServeRoute(id: route.id)
    assertTest(manager.load().serveRoutes.isEmpty, "ServeRoute removed successfully")

    unsetenv("TAIL_USERSPACE_DIR")
    try? FileManager.default.removeItem(at: tempDir)
} catch {
    print("Test 2 error: \(error)")
    failed += 1
}

// Test 3: ConfigManager RemoteProxies
do {
    let uniqueID = UUID().uuidString
    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tail_test_\(uniqueID)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    setenv("TAIL_USERSPACE_DIR", tempDir.path, 1)

    let manager = ConfigManager()
    let proxy = RemoteProxy(localPort: 8080, remoteHost: "nas.tail123.ts.net", remotePort: 80)
    assertTest(proxy.terminateTLS == false, "RemoteProxy default terminateTLS is false")
    try manager.addRemoteProxy(proxy)

    let tlsProxy = RemoteProxy(localPort: 9443, remoteHost: "secure.tail123.ts.net", remotePort: 443, terminateTLS: true)
    assertTest(tlsProxy.terminateTLS == true, "RemoteProxy terminateTLS true")
    try manager.addRemoteProxy(tlsProxy)

    let loaded = manager.load()
    assertTest(loaded.remoteProxies.count == 2, "RemoteProxies added successfully")
    assertTest(loaded.remoteProxies.first?.localPort == 8080, "RemoteProxy localPort matches")
    assertTest(loaded.remoteProxies.first?.remoteHost == "nas.tail123.ts.net", "RemoteProxy remoteHost matches")
    assertTest(loaded.remoteProxies.first?.remotePort == 80, "RemoteProxy remotePort matches")
    assertTest(loaded.remoteProxies.first?.terminateTLS == false, "RemoteProxy terminateTLS matches false")

    let loadedTLS = loaded.remoteProxies.first { $0.localPort == 9443 }
    assertTest(loadedTLS?.terminateTLS == true, "Loaded TLS proxy has terminateTLS == true")

    let updatedProxy = RemoteProxy(id: proxy.id, localPort: 8081, remoteHost: "nas2.tail123.ts.net", remotePort: 8080, terminateTLS: true, enabled: false)
    try manager.updateRemoteProxy(id: proxy.id, updatedProxy: updatedProxy)
    let reloadedProxy = manager.load().remoteProxies.first { $0.id == proxy.id }
    assertTest(reloadedProxy?.localPort == 8081, "RemoteProxy updated localPort matches 8081")
    assertTest(reloadedProxy?.remoteHost == "nas2.tail123.ts.net", "RemoteProxy updated remoteHost matches nas2")
    assertTest(reloadedProxy?.terminateTLS == true, "RemoteProxy updated terminateTLS matches true")
    assertTest(reloadedProxy?.enabled == false, "RemoteProxy updated enabled matches false")

    try manager.toggleRemoteProxy(id: proxy.id)
    assertTest(manager.load().remoteProxies.first { $0.id == proxy.id }?.enabled == true, "RemoteProxy toggle re-enables it")

    // Test 3b: Test external modification detection
    let anotherManager = ConfigManager()
    assertTest(anotherManager.load().remoteProxies.count == 2, "Another manager loads 2 proxies")
    var modifiedConfig = anotherManager.load()
    modifiedConfig.remoteProxies.removeFirst()
    try anotherManager.save(modifiedConfig)

    // Original manager should detect disk change and reload only 1 proxy
    let externallyReloaded = manager.load()
    assertTest(externallyReloaded.remoteProxies.count == 1, "Manager automatically detects external modification and reloads")

    try manager.removeRemoteProxy(id: tlsProxy.id)
    assertTest(manager.load().remoteProxies.isEmpty, "RemoteProxies removed successfully")

    // Test 3c: Backward compatibility decoding of RemoteProxy without terminateTLS field
    let legacyJSON = """
    {
        "id": "legacy-1",
        "localPort": 7070,
        "remoteHost": "legacy.ts.net",
        "remotePort": 80,
        "enabled": true
    }
    """.data(using: .utf8)!
    let decodedLegacy = try JSONDecoder().decode(RemoteProxy.self, from: legacyJSON)
    assertTest(decodedLegacy.terminateTLS == false, "Legacy RemoteProxy JSON without terminateTLS decodes to false")

    unsetenv("TAIL_USERSPACE_DIR")
    try? FileManager.default.removeItem(at: tempDir)
} catch {
    print("Test 3 error: \(error)")
    failed += 1
}

// Test 4: Binary Detection
if let tailscaled = DaemonSupervisor.findTailscaledBinary() {
    assertTest(FileManager.default.isExecutableFile(atPath: tailscaled), "Host tailscaled is executable: \(tailscaled)")
} else {
    print("  [INFO] No system tailscaled found; verified via environment override")
}

if let tailscaleCLI = TailscaleClient.findTailscaleCLI() {
    assertTest(FileManager.default.isExecutableFile(atPath: tailscaleCLI), "Host tailscale CLI is executable: \(tailscaleCLI)")
} else {
    print("  [INFO] No system tailscale CLI found; verified via environment override")
}

// Test environment variable override logic
do {
    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mock_bin_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let mockTailscaled = tempDir.appendingPathComponent("tailscaled")
    FileManager.default.createFile(atPath: mockTailscaled.path, contents: "#!/bin/sh\nexit 0".data(using: .utf8), attributes: [.posixPermissions: 0o755])
    setenv("TAILSCALED_PATH", mockTailscaled.path, 1)
    assertTest(DaemonSupervisor.findTailscaledBinary() == mockTailscaled.path, "tailscaled detected via TAILSCALED_PATH override")
    unsetenv("TAILSCALED_PATH")

    let mockCLI = tempDir.appendingPathComponent("tailscale")
    FileManager.default.createFile(atPath: mockCLI.path, contents: "#!/bin/sh\nexit 0".data(using: .utf8), attributes: [.posixPermissions: 0o755])
    setenv("TAILSCALE_CLI_PATH", mockCLI.path, 1)
    assertTest(TailscaleClient.findTailscaleCLI() == mockCLI.path, "tailscale CLI detected via TAILSCALE_CLI_PATH override")
    unsetenv("TAILSCALE_CLI_PATH")

    try? FileManager.default.removeItem(at: tempDir)
} catch {
    print("Test 4 mock error: \(error)")
    failed += 1
}

// Test 5: DaemonSupervisor initial state in clean directory
do {
    let uniqueID = UUID().uuidString
    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tail_test_\(uniqueID)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    setenv("TAIL_USERSPACE_DIR", tempDir.path, 1)

    let (running, pid) = DaemonSupervisor.shared.isRunning()
    assertTest(!running && pid == nil, "Daemon is not running in clean directory")

    unsetenv("TAIL_USERSPACE_DIR")
    try? FileManager.default.removeItem(at: tempDir)
} catch {
    print("Test 5 error: \(error)")
    failed += 1
}

// Test 6: SOCKS5Forwarder lifecycle
let forwarder = SOCKS5Forwarder.shared
assertTest(!forwarder.isProxyRunning(id: "fake-id"), "Unknown proxy ID is not running")
forwarder.stopAll()
assertTest(true, "stopAll completed cleanly")

// Test 7: Logger and VerbosityLevel
let logger = Logger.shared
logger.level = .normal
assertTest(logger.level == .normal, "Logger level normal")
logger.level = .verbose
assertTest(logger.level == .verbose, "Logger level updates to verbose")
logger.level = .debug
assertTest(logger.level == .debug, "Logger level updates to debug")
assertTest(VerbosityLevel.normal < VerbosityLevel.verbose, "VerbosityLevel ordering normal < verbose")
assertTest(VerbosityLevel.verbose < VerbosityLevel.debug, "VerbosityLevel ordering verbose < debug")
logger.level = .normal

// Test 8: ServeRoute Flexible Targets & Backward Compatibility
do {
    // 8a: URL target
    let urlRoute = ServeRoute(target: "http://localhost:3000/api", servePort: 443, proto: "https", path: "/api", proxyProtocol: 2)
    assertTest(urlRoute.target == "http://localhost:3000/api", "ServeRoute URL target matches")
    assertTest(urlRoute.localPort == 3000, "ServeRoute computed localPort parses 3000 from URL")
    assertTest(urlRoute.proxyProtocol == 2, "ServeRoute proxyProtocol matches 2")

    // 8b: Insecure HTTPS URL target
    let insecureRoute = ServeRoute(target: "https+insecure://localhost:8443", servePort: 443, proto: "https")
    assertTest(insecureRoute.target == "https+insecure://localhost:8443", "ServeRoute insecure HTTPS target matches")
    assertTest(insecureRoute.localPort == 8443, "ServeRoute computed localPort parses 8443 from insecure HTTPS")

    // 8c: Port string target
    let portRoute = ServeRoute(target: "8080", servePort: 8080, proto: "http")
    assertTest(portRoute.target == "8080", "ServeRoute port string target matches")
    assertTest(portRoute.localPort == 8080, "ServeRoute computed localPort parses 8080")

    // 8d: JSON Round-trip encoding & decoding
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let data = try encoder.encode(urlRoute)
    let decodedRoute = try decoder.decode(ServeRoute.self, from: data)
    assertTest(decodedRoute.target == "http://localhost:3000/api", "Round-trip decoded target matches")
    assertTest(decodedRoute.proxyProtocol == 2, "Round-trip decoded proxyProtocol matches")

    // 8e: Legacy JSON decoding without target field
    let legacyJSON = """
    {
        "id": "legacy-route-1",
        "localPort": 9000,
        "servePort": 443,
        "proto": "https",
        "path": "/legacy",
        "enabled": true
    }
    """.data(using: .utf8)!
    let decodedLegacy = try decoder.decode(ServeRoute.self, from: legacyJSON)
    assertTest(decodedLegacy.target == "9000", "Legacy JSON decodes localPort into target")
    assertTest(decodedLegacy.localPort == 9000, "Legacy JSON computed localPort matches 9000")
} catch {
    print("Test 8 error: \(error)")
    failed += 1
}

// Test 9: Ephemeral CLI Sessions Lifecycle & Stale Cleanup
do {
    let uniqueID = UUID().uuidString
    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tail_test_\(uniqueID)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    setenv("TAIL_USERSPACE_DIR", tempDir.path, 1)

    let manager = ConfigManager()
    assertTest(manager.loadEphemeralSessions().isEmpty, "Initially no ephemeral sessions")

    let currentPID = getpid()
    let activeRoute = ServeRoute(target: "5000", servePort: 5000, proto: "http")
    let activeSession = EphemeralServeSession(id: "sess-1", pid: currentPID, route: activeRoute, createdAt: Date())
    try manager.saveEphemeralSession(activeSession)

    let deadPID: Int32 = 9999999
    let deadRoute = ServeRoute(target: "6000", servePort: 6000, proto: "http")
    let deadSession = EphemeralServeSession(id: "sess-2", pid: deadPID, route: deadRoute, createdAt: Date())
    try manager.saveEphemeralSession(deadSession)

    assertTest(manager.loadEphemeralSessions().count == 2, "2 ephemeral sessions saved")

    let alive = manager.cleanupStaleEphemeralSessions()
    assertTest(alive.count == 1, "cleanupStaleEphemeralSessions pruned dead PID")
    assertTest(alive.first?.pid == currentPID, "Active session with current PID remains alive")

    try manager.removeEphemeralSession(id: "sess-1")
    assertTest(manager.loadEphemeralSessions().isEmpty, "Removed active ephemeral session cleanly")

    unsetenv("TAIL_USERSPACE_DIR")
    try? FileManager.default.removeItem(at: tempDir)
} catch {
    print("Test 9 error: \(error)")
    failed += 1
}

// Test 10: Model Context Protocol (MCP) Server Suite
do {
    let uniqueID = UUID().uuidString
    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tail_mcp_test_\(uniqueID)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    setenv("TAIL_USERSPACE_DIR", tempDir.path, 1)

    let testConfigManager = ConfigManager()
    let testServer = MCPServer(
        client: TailscaleClient.shared,
        supervisor: DaemonSupervisor.shared,
        configManager: testConfigManager,
        forwarder: SOCKS5Forwarder.shared
    )

    // Helper to send JSON string and get response dictionary
    func sendMCP(_ reqObj: [String: Any]) -> [String: Any]? {
        guard let data = try? JSONSerialization.data(withJSONObject: reqObj) else { return nil }
        guard let resData = testServer.handleMessageData(data) else { return nil }
        return try? JSONSerialization.jsonObject(with: resData) as? [String: Any]
    }

    // 10a: Handshake (initialize)
    let initReq: [String: Any] = [
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": [
            "protocolVersion": "2024-11-05",
            "capabilities": [:] as [String: Any],
            "clientInfo": ["name": "test-client", "version": "1.0"]
        ]
    ]
    let initRes = sendMCP(initReq)
    assertTest(initRes?["jsonrpc"] as? String == "2.0", "MCP initialize returns jsonrpc 2.0")
    assertTest(initRes?["id"] as? Int == 1, "MCP initialize returns matching id 1")
    let initResult = initRes?["result"] as? [String: Any]
    assertTest(initResult?["protocolVersion"] as? String == "2024-11-05", "MCP protocolVersion matches 2024-11-05")
    let serverInfo = initResult?["serverInfo"] as? [String: Any]
    assertTest(serverInfo?["name"] as? String == "tail-userspace", "MCP serverInfo name is tail-userspace")
    let caps = initResult?["capabilities"] as? [String: Any]
    assertTest(caps?["tools"] != nil && caps?["resources"] != nil && caps?["prompts"] != nil, "MCP capabilities contain tools, resources, prompts")

    // 10b: Notification initialized
    let notifReq: [String: Any] = [
        "jsonrpc": "2.0",
        "method": "notifications/initialized",
        "params": [:] as [String: Any]
    ]
    let notifRes = sendMCP(notifReq)
    assertTest(notifRes == nil, "MCP notification returns nil (no response)")

    // 10c: Ping
    let pingReq: [String: Any] = [
        "jsonrpc": "2.0",
        "id": "ping-123",
        "method": "ping"
    ]
    let pingRes = sendMCP(pingReq)
    assertTest(pingRes?["id"] as? String == "ping-123", "MCP ping returns string id")
    assertTest((pingRes?["result"] as? [String: Any])?.isEmpty == true, "MCP ping returns empty result object")

    // 10d: Tools List
    let toolsReq: [String: Any] = [
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/list"
    ]
    let toolsRes = sendMCP(toolsReq)
    let toolsList = (toolsRes?["result"] as? [String: Any])?["tools"] as? [[String: Any]] ?? []
    assertTest(toolsList.count >= 19, "MCP tools/list returns at least 19 tools (got \(toolsList.count))")
    let toolNames = Set(toolsList.compactMap { $0["name"] as? String })
    let requiredTools: Set<String> = [
        "get_status", "daemon_start", "daemon_stop", "connect", "disconnect",
        "get_env", "get_daemon_logs", "list_serve_routes", "add_serve_route",
        "remove_serve_route", "reapply_serve_routes", "reset_serve", "get_serve_status",
        "list_remote_proxies", "add_remote_proxy", "remove_remote_proxy",
        "toggle_remote_proxy", "get_config", "update_config"
    ]
    assertTest(requiredTools.isSubset(of: toolNames), "All expected tool names exist in tools/list")

    // 10e: Tool Call get_status
    let statusCallReq: [String: Any] = [
        "jsonrpc": "2.0",
        "id": 3,
        "method": "tools/call",
        "params": [
            "name": "get_status",
            "arguments": [:] as [String: Any]
        ]
    ]
    let statusCallRes = sendMCP(statusCallReq)
    let statusCallResult = statusCallRes?["result"] as? [String: Any]
    assertTest(statusCallResult?["isError"] as? Bool == false, "get_status isError == false")
    let statusContent = (statusCallResult?["content"] as? [[String: Any]])?.first?["text"] as? String ?? ""
    assertTest(statusContent.contains("Tailscale Userspace Daemon Status"), "get_status content contains header")

    // 10f: Tool Call get_env
    let envCallReq: [String: Any] = [
        "jsonrpc": "2.0",
        "id": 4,
        "method": "tools/call",
        "params": [
            "name": "get_env",
            "arguments": [:] as [String: Any]
        ]
    ]
    let envCallRes = sendMCP(envCallReq)
    let envContent = ((envCallRes?["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String ?? ""
    assertTest(envContent.contains("export ALL_PROXY=socks5://127.0.0.1:"), "get_env contains export ALL_PROXY")

    // 10g: Tool Call get_config
    let configCallReq: [String: Any] = [
        "jsonrpc": "2.0",
        "id": 5,
        "method": "tools/call",
        "params": [
            "name": "get_config",
            "arguments": [:] as [String: Any]
        ]
    ]
    let configCallRes = sendMCP(configCallReq)
    let configContent = ((configCallRes?["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String ?? ""
    assertTest(configContent.contains("socks5Port"), "get_config content contains socks5Port")

    // 10h: Tool Call add_remote_proxy & list & toggle & remove
    let addProxyReq: [String: Any] = [
        "jsonrpc": "2.0",
        "id": 6,
        "method": "tools/call",
        "params": [
            "name": "add_remote_proxy",
            "arguments": [
                "localPort": 18080,
                "remoteHost": "nas.tailnet.ts.net",
                "remotePort": 80,
                "terminateTLS": true
            ]
        ]
    ]
    let addProxyRes = sendMCP(addProxyReq)
    let addProxyText = ((addProxyRes?["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String ?? ""
    assertTest(addProxyText.contains("localhost:18080"), "add_remote_proxy text contains localhost:18080")
    assertTest(testConfigManager.load().remoteProxies.contains { $0.localPort == 18080 && $0.terminateTLS }, "Proxy saved in config with TLS")

    let listProxiesReq: [String: Any] = [
        "jsonrpc": "2.0",
        "id": 7,
        "method": "tools/call",
        "params": ["name": "list_remote_proxies", "arguments": [:] as [String: Any]]
    ]
    let listProxiesRes = sendMCP(listProxiesReq)
    let listProxiesText = ((listProxiesRes?["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String ?? ""
    assertTest(listProxiesText.contains("localhost:18080"), "list_remote_proxies text contains localhost:18080")

    let toggleProxyReq: [String: Any] = [
        "jsonrpc": "2.0",
        "id": 8,
        "method": "tools/call",
        "params": ["name": "toggle_remote_proxy", "arguments": ["localPort": 18080]]
    ]
    let toggleProxyRes = sendMCP(toggleProxyReq)
    let toggleProxyText = ((toggleProxyRes?["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String ?? ""
    assertTest(toggleProxyText.contains("disabled"), "toggle_remote_proxy toggled to disabled")

    let removeProxyReq: [String: Any] = [
        "jsonrpc": "2.0",
        "id": 9,
        "method": "tools/call",
        "params": ["name": "remove_remote_proxy", "arguments": ["localPort": 18080]]
    ]
    let removeProxyRes = sendMCP(removeProxyReq)
    let removeProxyText = ((removeProxyRes?["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String ?? ""
    assertTest(removeProxyText.contains("Remote proxy removed"), "remove_remote_proxy succeeded")
    assertTest(!testConfigManager.load().remoteProxies.contains { $0.localPort == 18080 }, "Proxy removed from config")

    // 10i: Tool Call add_serve_route & list & remove
    let addServeReq: [String: Any] = [
        "jsonrpc": "2.0",
        "id": 10,
        "method": "tools/call",
        "params": [
            "name": "add_serve_route",
            "arguments": [
                "target": "3000",
                "path": "/api",
                "servePort": 8443,
                "proto": "https"
            ]
        ]
    ]
    let addServeRes = sendMCP(addServeReq)
    let addServeText = ((addServeRes?["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String ?? ""
    assertTest(addServeText.contains("Serve route created"), "add_serve_route succeeded")
    assertTest(testConfigManager.load().serveRoutes.contains { $0.servePort == 8443 && $0.path == "/api" }, "Serve route saved in config")

    let listServeReq: [String: Any] = [
        "jsonrpc": "2.0",
        "id": 11,
        "method": "tools/call",
        "params": ["name": "list_serve_routes", "arguments": [:] as [String: Any]]
    ]
    let listServeRes = sendMCP(listServeReq)
    let listServeText = ((listServeRes?["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String ?? ""
    assertTest(listServeText.contains("3000") && listServeText.contains("/api"), "list_serve_routes contains 3000 and /api")

    let removeServeReq: [String: Any] = [
        "jsonrpc": "2.0",
        "id": 12,
        "method": "tools/call",
        "params": ["name": "remove_serve_route", "arguments": ["target": "3000", "path": "/api", "servePort": 8443]]
    ]
    let removeServeRes = sendMCP(removeServeReq)
    let removeServeText = ((removeServeRes?["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String ?? ""
    assertTest(removeServeText.contains("Removed serve route"), "remove_serve_route succeeded")
    assertTest(!testConfigManager.load().serveRoutes.contains { $0.servePort == 8443 }, "Serve route removed from config")

    // 10j: Resources List & Read
    let resListReq: [String: Any] = [
        "jsonrpc": "2.0",
        "id": 13,
        "method": "resources/list"
    ]
    let resListRes = sendMCP(resListReq)
    let resList = (resListRes?["result"] as? [String: Any])?["resources"] as? [[String: Any]] ?? []
    assertTest(resList.count >= 5, "MCP resources/list returns at least 5 resources")
    let resURIs = Set(resList.compactMap { $0["uri"] as? String })
    assertTest(resURIs.contains("tailuserspace://status"), "resources include tailuserspace://status")
    assertTest(resURIs.contains("tailuserspace://config"), "resources include tailuserspace://config")

    let resReadReq: [String: Any] = [
        "jsonrpc": "2.0",
        "id": 14,
        "method": "resources/read",
        "params": ["uri": "tailuserspace://config"]
    ]
    let resReadRes = sendMCP(resReadReq)
    let readContents = (resReadRes?["result"] as? [String: Any])?["contents"] as? [[String: Any]]
    let readText = readContents?.first?["text"] as? String ?? ""
    assertTest(readText.contains("socks5Port"), "resources/read tailuserspace://config returns valid json with socks5Port")

    // 10k: Prompts List & Get
    let promptsListReq: [String: Any] = [
        "jsonrpc": "2.0",
        "id": 15,
        "method": "prompts/list"
    ]
    let promptsListRes = sendMCP(promptsListReq)
    let promptsList = (promptsListRes?["result"] as? [String: Any])?["prompts"] as? [[String: Any]] ?? []
    assertTest(promptsList.count >= 3, "MCP prompts/list returns at least 3 prompts")

    let promptGetReq: [String: Any] = [
        "jsonrpc": "2.0",
        "id": 16,
        "method": "prompts/get",
        "params": ["name": "diagnose", "arguments": [:] as [String: Any]]
    ]
    let promptGetRes = sendMCP(promptGetReq)
    let promptMessages = (promptGetRes?["result"] as? [String: Any])?["messages"] as? [[String: Any]]
    let promptText = (promptMessages?.first?["content"] as? [String: Any])?["text"] as? String ?? ""
    assertTest(promptText.contains("TailUserspace instance"), "prompts/get diagnose returns expected content")

    // 10l: Error Handling (Unknown method, Invalid JSON, Unknown tool)
    let unknownMethodReq: [String: Any] = [
        "jsonrpc": "2.0",
        "id": 17,
        "method": "unknown/nonexistent"
    ]
    let unknownRes = sendMCP(unknownMethodReq)
    let errObj = unknownRes?["error"] as? [String: Any]
    assertTest(errObj?["code"] as? Int == MCPProtocol.methodNotFound, "Unknown method returns methodNotFound code (-32601)")

    let invalidJsonData = "This is not JSON\n".data(using: .utf8)!
    let parseErrData = testServer.handleMessageData(invalidJsonData)
    let parseErrObj = (try? JSONSerialization.jsonObject(with: parseErrData!) as? [String: Any])?["error"] as? [String: Any]
    assertTest(parseErrObj?["code"] as? Int == MCPProtocol.parseError, "Invalid JSON returns parseError code (-32700)")

    let unknownToolReq: [String: Any] = [
        "jsonrpc": "2.0",
        "id": 18,
        "method": "tools/call",
        "params": ["name": "completely_fake_tool"]
    ]
    let unknownToolRes = sendMCP(unknownToolReq)
    let unknownToolResult = unknownToolRes?["result"] as? [String: Any]
    assertTest(unknownToolResult?["isError"] as? Bool == true, "Unknown tool call returns isError: true")

    // 10m: End-to-end pipe streaming (multi-message I/O)
    let inputPipe = Pipe()
    let outputPipe = Pipe()

    let msg1 = "{\"jsonrpc\":\"2.0\",\"id\":101,\"method\":\"ping\"}\n"
    let msg2 = "{\"jsonrpc\":\"2.0\",\"id\":102,\"method\":\"ping\"}\n"
    inputPipe.fileHandleForWriting.write(msg1.data(using: .utf8)!)
    inputPipe.fileHandleForWriting.write(msg2.data(using: .utf8)!)
    try? inputPipe.fileHandleForWriting.close()

    testServer.run(inputHandle: inputPipe.fileHandleForReading, outputHandle: outputPipe.fileHandleForWriting)
    try? outputPipe.fileHandleForWriting.close()

    let streamOutData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let streamOutStr = String(data: streamOutData, encoding: .utf8) ?? ""
    let lines = streamOutStr.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    assertTest(lines.count == 2, "Stream processed 2 messages over pipes")
    assertTest(lines[0].contains("\"id\":101") && lines[1].contains("\"id\":102"), "Stream output contains matching message IDs")

    unsetenv("TAIL_USERSPACE_DIR")
    try? FileManager.default.removeItem(at: tempDir)
} catch {
    print("Test 10 error: \(error)")
    failed += 1
}

// Test 11: Model Context Protocol (MCP) HTTP Server Suite
do {
    let testPort = 19858
    let httpServer = MCPHTTPServer.shared
    try httpServer.start(port: testPort)
    assertTest(httpServer.isRunning, "MCPHTTPServer started and isRunning == true")
    assertTest(httpServer.port == testPort, "MCPHTTPServer port matches testPort")

    // Synchronous HTTP helper
    func sendHTTPRequest(
        method: String,
        path: String,
        headers: [String: String] = [:],
        body: Data? = nil
    ) -> (status: Int, headers: [String: String], data: Data)? {
        guard let url = URL(string: "http://127.0.0.1:\(testPort)\(path)") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = method
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }
        request.httpBody = body
        request.timeoutInterval = 5.0

        let semaphore = DispatchSemaphore(value: 0)
        var responseStatus = 0
        var responseHeaders: [String: String] = [:]
        var responseData = Data()

        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse {
                responseStatus = http.statusCode
                for (k, v) in http.allHeaderFields {
                    if let keyStr = k as? String, let valStr = v as? String {
                        responseHeaders[keyStr.lowercased()] = valStr
                    }
                }
            }
            if let data = data {
                responseData = data
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 5.0)

        guard responseStatus > 0 else { return nil }
        return (responseStatus, responseHeaders, responseData)
    }

    // 11a: GET / status info
    if let res = sendHTTPRequest(method: "GET", path: "/") {
        assertTest(res.status == 200, "GET / returns 200 OK")
        let json = (try? JSONSerialization.jsonObject(with: res.data)) as? [String: Any]
        assertTest(json?["status"] as? String == "online", "GET / status is online")
        assertTest(json?["name"] as? String == "tail-userspace", "GET / name is tail-userspace")
        let endpoints = json?["endpoints"] as? [String: String]
        assertTest(endpoints?["mcp"] != nil && endpoints?["sse"] != nil, "GET / returns mcp and sse endpoints")
    } else {
        assertTest(false, "GET / request failed")
    }

    // 11b: POST /mcp initialize
    let initBody: [String: Any] = [
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": ["protocolVersion": "2024-11-05", "capabilities": [:] as [String: Any]]
    ]
    let initData = try JSONSerialization.data(withJSONObject: initBody)
    if let res = sendHTTPRequest(method: "POST", path: "/mcp", headers: ["Content-Type": "application/json"], body: initData) {
        assertTest(res.status == 200, "POST /mcp initialize returns 200 OK")
        let json = (try? JSONSerialization.jsonObject(with: res.data)) as? [String: Any]
        let result = json?["result"] as? [String: Any]
        assertTest(result?["protocolVersion"] as? String == "2024-11-05", "HTTP initialize returns protocolVersion 2024-11-05")
    } else {
        assertTest(false, "POST /mcp initialize request failed")
    }

    // 11c: POST /mcp tools/list
    let toolsBody: [String: Any] = [
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/list"
    ]
    let toolsData = try JSONSerialization.data(withJSONObject: toolsBody)
    if let res = sendHTTPRequest(method: "POST", path: "/mcp", headers: ["Content-Type": "application/json"], body: toolsData) {
        assertTest(res.status == 200, "POST /mcp tools/list returns 200 OK")
        let json = (try? JSONSerialization.jsonObject(with: res.data)) as? [String: Any]
        let tools = (json?["result"] as? [String: Any])?["tools"] as? [[String: Any]] ?? []
        assertTest(tools.count >= 19, "HTTP tools/list returns at least 19 tools")
    } else {
        assertTest(false, "POST /mcp tools/list request failed")
    }

    // 11d: POST /mcp tools/call get_status
    let callBody: [String: Any] = [
        "jsonrpc": "2.0",
        "id": 3,
        "method": "tools/call",
        "params": [
            "name": "get_status",
            "arguments": [:] as [String: Any]
        ]
    ]
    let callData = try JSONSerialization.data(withJSONObject: callBody)
    if let res = sendHTTPRequest(method: "POST", path: "/mcp", headers: ["Content-Type": "application/json"], body: callData) {
        assertTest(res.status == 200, "POST /mcp tools/call returns 200 OK")
        let json = (try? JSONSerialization.jsonObject(with: res.data)) as? [String: Any]
        let result = json?["result"] as? [String: Any]
        assertTest(result?["isError"] as? Bool == false, "HTTP tools/call isError == false")
        let text = ((result?["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        assertTest(text.contains("Tailscale Userspace Daemon Status"), "HTTP tools/call returns status text")
    } else {
        assertTest(false, "POST /mcp tools/call request failed")
    }

    // 11e: OPTIONS /mcp CORS preflight
    if let res = sendHTTPRequest(method: "OPTIONS", path: "/mcp") {
        assertTest(res.status == 204, "OPTIONS /mcp returns 204 No Content")
        assertTest(res.headers["access-control-allow-origin"] == "*", "OPTIONS /mcp includes CORS allow-origin")
        assertTest(res.headers["access-control-allow-methods"]?.contains("POST") == true, "OPTIONS /mcp includes CORS POST method")
    } else {
        assertTest(false, "OPTIONS /mcp request failed")
    }

    // 11f: POST /messages with direct JSON-RPC and dual return
    let messageBody: [String: Any] = [
        "jsonrpc": "2.0",
        "id": 4,
        "method": "tools/call",
        "params": [
            "name": "get_env",
            "arguments": [:] as [String: Any]
        ]
    ]
    let msgData = try JSONSerialization.data(withJSONObject: messageBody)
    if let res = sendHTTPRequest(method: "POST", path: "/messages", headers: ["Content-Type": "application/json"], body: msgData) {
        assertTest(res.status == 200, "POST /messages returns 200 OK")
        let json = (try? JSONSerialization.jsonObject(with: res.data)) as? [String: Any]
        let text = (((json?["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        assertTest(text.contains("export ALL_PROXY="), "POST /messages returned env script in body")
    } else {
        assertTest(false, "POST /messages request failed")
    }

    // 11g: Stop HTTP Server
    httpServer.stop()
    assertTest(!httpServer.isRunning, "MCPHTTPServer stopped cleanly")
} catch {
    print("Test 11 error: \(error)")
    failed += 1
}

print("\n=== Test Results: \(passed) passed, \(failed) failed ===")
if failed > 0 {
    exit(1)
}
