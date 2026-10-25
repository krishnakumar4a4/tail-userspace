# Model Context Protocol (MCP) HTTP Server Interface

TailUserspace includes an embedded, high-performance **HTTP & Server-Sent Events (SSE)** server implementing the open [Model Context Protocol (MCP)](https://modelcontextprotocol.io/) specification over JSON-RPC 2.0.

### 🌟 Zero CLI Dependency (Menu Bar App is All You Need)
Unlike stdio-based MCP servers that require configuring paths to external CLI executables, TailUserspace runs its HTTP MCP server **directly inside the menu bar application (`TailUserspace.app`)**. 

As long as `TailUserspace.app` is running in your macOS menu bar:
* **No CLI installation required**: You do not need `tail-userspace` installed in your shell `$PATH`.
* **Instant connection**: Any AI assistant (Claude Desktop, Cursor, Google Antigravity, Gemini CLI, VS Code Cline/Roo Code, Zed) connects directly over local HTTP.
* **Dual Transport**: Supports both direct HTTP POST (`http://127.0.0.1:1058/mcp`) and Server-Sent Events (`http://127.0.0.1:1058/sse`).

---

## 1. Quick Setup & Client Configuration

### Claude Desktop
Add TailUserspace to your Claude Desktop configuration file at `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "tail-userspace": {
      "url": "http://127.0.0.1:1058/mcp"
    }
  }
}
```

### Cursor
Add to `.cursor/mcp.json` in your project or global Cursor settings:

```json
{
  "mcpServers": {
    "tail-userspace": {
      "url": "http://127.0.0.1:1058/mcp"
    }
  }
}
```

### Google Antigravity / Gemini CLI
Add to your Antigravity or Gemini CLI MCP configuration:

```json
{
  "mcpServers": {
    "tail-userspace": {
      "url": "http://127.0.0.1:1058/mcp"
    }
  }
}
```

### VS Code (Cline / Roo Code)
Add to your extension settings:

```json
{
  "mcpServers": {
    "tail-userspace": {
      "url": "http://127.0.0.1:1058/mcp"
    }
  }
}
```

### Zed Editor
Add to `~/.config/zed/settings.json`:

```json
{
  "context_servers": {
    "tail-userspace": {
      "url": "http://127.0.0.1:1058/mcp"
    }
  }
}
```

---

## 2. Endpoints & Protocol Transport

| Endpoint | HTTP Method | Transport Type | Description |
| :--- | :--- | :--- | :--- |
| `http://127.0.0.1:1058/mcp` | `POST` | Direct JSON-RPC | Client sends JSON-RPC requests; server responds with HTTP 200 and result JSON. |
| `http://127.0.0.1:1058/sse` | `GET` | Server-Sent Events | Opens persistent SSE stream; server sends initial `endpoint` event pointing to `/messages`. |
| `http://127.0.0.1:1058/messages` | `POST` | SSE Postback | Client sends JSON-RPC requests; server dispatches response both over SSE stream and in HTTP body. |
| `http://127.0.0.1:1058/` | `GET` | Health / Discovery | Returns server status, protocol version, and available endpoints JSON. |

*CORS preflight (`OPTIONS`) is fully supported across all endpoints for web-based tools.*

---

## 3. Running Headless or via CLI (Optional)

If running in a headless server environment without the GUI menu bar app:

```bash
# Start HTTP MCP server in foreground:
tail-userspace mcp

# Customize port:
tail-userspace mcp --port=1080

# View configuration help:
tail-userspace mcp --help

# Optional: Run in legacy stdio mode if needed:
tail-userspace mcp --stdio
```

---

## 4. Available Tools Reference (19 Tools)

| Tool Name | Parameters | Description |
| :--- | :--- | :--- |
| `get_status` | *(none)* | Live status of the unprivileged daemon (PID, backend state, IPs, MagicDNS domain, auth URLs, health warnings, MCP server URL, route counts). |
| `daemon_start` | *(none)* | Starts the unprivileged userspace daemon, activates configured proxies, and reapplies active serve routes. |
| `daemon_stop` | *(none)* | Gracefully shuts down the userspace daemon and terminates all outbound proxy forwarders. |
| `connect` | `extraArgs` (array), `timeout` (number), `openBrowser` (bool) | Connects local node to tailnet (`tailscale up`). If authorization is required, returns the interactive auth URL. |
| `disconnect` | *(none)* | Disconnects local node from the tailnet (`tailscale down`). |
| `get_env` | *(none)* | Returns shell export statements (`ALL_PROXY`, `HTTP_PROXY`, `HTTPS_PROXY`) configured for the active userspace proxy ports. |
| `get_daemon_logs` | `lines` (int, default: 50, max: 500) | Reads recent lines from `~/Library/Logs/TailUserspace/tailscaled.log`. |
| `list_serve_routes` | *(none)* | Lists configured Inbound Serve routes with live synchronization status against the daemon and any active ephemeral CLI sessions. |
| `add_serve_route` | `target` (string, required), `servePort` (int), `proto` (string), `path` (string), `proxyProtocol` (int), `background` (bool) | Exposes a local port, URL, or service to the tailnet via HTTPS (port 443) or TCP with automated Let's Encrypt certificates. |
| `remove_serve_route` | `id` (string), `target` (string), `servePort` (int), `path` (string), `proto` (string) | Removes an inbound serve route from configuration and unmounts it from the live daemon. |
| `reapply_serve_routes` | *(none)* | Reapplies and synchronizes all configured persistent serve routes to the live running daemon. |
| `reset_serve` | *(none)* | Resets and clears all active Tailscale Serve endpoints on the running daemon. |
| `get_serve_status` | `json` (bool, default: false) | Retrieves live status from `tailscale serve status` (raw text or parsed JSON). |
| `list_remote_proxies` | *(none)* | Lists all configured Outbound Remote Proxies and checks if their local TCP listeners are actively running. |
| `add_remote_proxy` | `localPort` (int, required), `remoteHost` (string, required), `remotePort` (int), `terminateTLS` (bool) | Forwards a local port to a remote tailnet machine. Supports native TLS termination (`terminateTLS: true`) to expose HTTPS backends as plain HTTP locally. |
| `remove_remote_proxy` | `localPort` (int), `id` (string) | Removes an outbound proxy and shuts down its local TCP listener. |
| `toggle_remote_proxy` | `localPort` (int), `id` (string) | Enables or disables an outbound proxy without deleting its configuration. |
| `get_config` | *(none)* | Reads current persistent `config.json` containing proxy ports and routes. |
| `update_config` | `socks5Port` (int), `httpProxyPort` (int), `mcpPort` (int), `mcpEnabled` (bool), `autoStart` (bool) | Updates persistent settings such as proxy ports, MCP server port, or auto-start behavior. |

---

## 5. Available Resources Reference (5 Resources)

| Resource URI | MIME Type | Description |
| :--- | :--- | :--- |
| `tailuserspace://status` | `application/json` | Real-time daemon process state, backend state, IPs, domain, and proxy/MCP ports. |
| `tailuserspace://config` | `application/json` | Full contents of the user's `config.json`. |
| `tailuserspace://serve` | `application/json` | Configured serve routes, live discrepancies, and active ephemeral CLI sessions. |
| `tailuserspace://proxies` | `application/json` | Configured outbound remote proxies with live listener states. |
| `tailuserspace://logs` | `text/plain` | Last 100 lines of `tailscaled.log`. |

---

## 6. Available Prompt Templates (3 Prompts)

1. **`diagnose`**: Performs a comprehensive health check on daemon status, network connectivity, serve routes, and proxy listeners, recommending corrective actions if discrepancies or failures are detected.
2. **`expose-service`**: Guides the assistant in configuring an inbound HTTPS serve endpoint for a local web server, container, or development port.
3. **`tunnel-remote-service`**: Guides the assistant in establishing an outbound SOCKS5 tunnel to reach a remote tailnet machine (e.g. database, NAS, or internal web UI) from localhost.
