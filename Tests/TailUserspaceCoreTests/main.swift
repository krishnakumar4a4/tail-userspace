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
    try manager.addRemoteProxy(proxy)

    let loaded = manager.load()
    assertTest(loaded.remoteProxies.count == 1, "RemoteProxy added successfully")
    assertTest(loaded.remoteProxies.first?.localPort == 8080, "RemoteProxy localPort matches")
    assertTest(loaded.remoteProxies.first?.remoteHost == "nas.tail123.ts.net", "RemoteProxy remoteHost matches")
    assertTest(loaded.remoteProxies.first?.remotePort == 80, "RemoteProxy remotePort matches")

    try manager.toggleRemoteProxy(id: proxy.id)
    assertTest(manager.load().remoteProxies.first?.enabled == false, "RemoteProxy toggle disables it")

    try manager.removeRemoteProxy(id: proxy.id)
    assertTest(manager.load().remoteProxies.isEmpty, "RemoteProxy removed successfully")

    unsetenv("TAIL_USERSPACE_DIR")
    try? FileManager.default.removeItem(at: tempDir)
} catch {
    print("Test 3 error: \(error)")
    failed += 1
}

// Test 4: Binary Detection
let tailscaled = DaemonSupervisor.findTailscaledBinary()
assertTest(tailscaled != nil, "tailscaled binary found on host system")

let tailscaleCLI = TailscaleClient.findTailscaleCLI()
assertTest(tailscaleCLI != nil, "tailscale CLI binary found on host system")

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

print("\n=== Test Results: \(passed) passed, \(failed) failed ===")
if failed > 0 {
    exit(1)
}
