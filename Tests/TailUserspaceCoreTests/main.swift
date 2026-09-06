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

    try manager.toggleRemoteProxy(id: proxy.id)
    assertTest(manager.load().remoteProxies.first { $0.id == proxy.id }?.enabled == false, "RemoteProxy toggle disables it")

    try manager.removeRemoteProxy(id: proxy.id)
    try manager.removeRemoteProxy(id: tlsProxy.id)
    assertTest(manager.load().remoteProxies.isEmpty, "RemoteProxies removed successfully")

    // Test 3b: Backward compatibility decoding of RemoteProxy without terminateTLS field
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

print("\n=== Test Results: \(passed) passed, \(failed) failed ===")
if failed > 0 {
    exit(1)
}
