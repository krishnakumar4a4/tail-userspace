import Foundation
import TailUserspaceCore

let rawArgs = CommandLine.arguments.dropFirst()
if rawArgs.contains("--stdio") {
    MCPServer.shared.runStdio()
} else {
    let config = ConfigManager.shared.load()
    var port = config.mcpPort
    for arg in rawArgs {
        if arg.hasPrefix("--port="), let p = Int(arg.split(separator: "=").last ?? "") {
            port = p
        }
    }
    do {
        try MCPHTTPServer.shared.start(port: port)
        print("✓ TailUserspace MCP HTTP Server running on http://127.0.0.1:\(port)/mcp")
        dispatchMain()
    } catch {
        print("● MCP HTTP Server already running on port \(port)")
        exit(0)
    }
}
