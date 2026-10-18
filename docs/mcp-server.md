# Model Context Protocol (MCP) Server Interface

TailUserspace includes a native, full-featured **Model Context Protocol (MCP)** server interface conforming to the open [Model Context Protocol](https://modelcontextprotocol.io/) specification over JSON-RPC 2.0.

This interface allows AI coding assistants—including **Claude Desktop**, **Cursor**, **Google Antigravity**, **Gemini CLI**, **VS Code (Cline / Roo Code)**, and **Zed**—to directly monitor, diagnose, and orchestrate Tailscale userspace networking without manual terminal commands or context switching.

---

## 1. Quick Start & Execution

The MCP server operates over standard I/O (`stdin` / `stdout`) using newline-delimited JSON-RPC 2.0 messages. All logging and diagnostic output are automatically redirected to `stderr`, preserving stdout strictly for pure JSON-RPC messages.

You can launch the MCP server in two ways:

```bash
# Via the CLI subcommand:
tail-userspace mcp

# Via the dedicated standalone executable:
tail-userspace-mcp

# View configuration snippets and tool reference:
tail-userspace mcp --help
```

---

## 2. Client Configuration

### Claude Desktop
Add TailUserspace to your Claude Desktop configuration file at `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "tail-userspace": {
      "command": "/usr/local/bin/tail-userspace",
      "args": ["mcp"]
    }
  }
}
```

*(If installed in another directory or built from source, replace `/usr/local/bin/tail-userspace` with the path to your executable or use `tail-userspace-mcp` without args).*

### Cursor
Add to `.cursor/mcp.json` in your workspace or global Cursor settings:

```json
{
  "mcpServers": {
    "tail-userspace": {
      "command": "tail-userspace",
      "args": ["mcp"]
    }
  }
}
```

### Google Antigravity / Gemini CLI
Add to your Antigravity or Gemini CLI MCP configuration in `~/.gemini/antigravity-cli/mcp/` or project configuration:

```json
{
  "mcpServers": {
    "tail-userspace": {
      "command": "tail-userspace",
      "args": ["mcp"]
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
      "command": "tail-userspace",
      "args": ["mcp"]
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
      "command": {
        "path": "tail-userspace",
        "args": ["mcp"]
      }
    }
  }
}
```

---

## 3. Available Tools Reference (19 Tools)

| Tool Name | Parameters | Description |
| :--- | :--- | :--- |
| `get_status` | *(none)* | Live status of the unprivileged daemon (PID, backend state, IPs, MagicDNS domain, auth URLs, health warnings, route counts). |
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
| `update_config` | `socks5Port` (int), `httpProxyPort` (int), `autoStart` (bool) | Updates persistent settings such as proxy ports or auto-start behavior. |

---

## 4. Available Resources Reference (5 Resources)

MCP resources allow AI clients supporting resource subscriptions or direct inspection to read live application state:

| Resource URI | MIME Type | Description |
| :--- | :--- | :--- |
| `tailuserspace://status` | `application/json` | Real-time daemon process state, backend state, IPs, domain, and proxy ports. |
| `tailuserspace://config` | `application/json` | Full contents of the user's `config.json`. |
| `tailuserspace://serve` | `application/json` | Configured serve routes, live discrepancies, and active ephemeral CLI sessions. |
| `tailuserspace://proxies` | `application/json` | Configured outbound remote proxies with live listener states. |
| `tailuserspace://logs` | `text/plain` | Last 100 lines of `tailscaled.log`. |

---

## 5. Available Prompt Templates (3 Prompts)

Pre-built prompt templates guide the AI assistant in performing common workflows:

1. **`diagnose`**: Performs a comprehensive health check on daemon status, network connectivity, serve routes, and proxy listeners, recommending corrective actions if discrepancies or failures are detected.
2. **`expose-service`**: Guides the assistant in configuring an inbound HTTPS serve endpoint for a local web server, container, or development port.
3. **`tunnel-remote-service`**: Guides the assistant in establishing an outbound SOCKS5 tunnel to reach a remote tailnet machine (e.g. database, NAS, or internal web UI) from localhost.

---

## 6. Example AI Interactions

### Example 1: Exposing a Local Development Server
**User prompt to AI assistant:**
> "Expose my local Next.js app running on localhost:3000 to my tailnet so my team can test it."

**Assistant execution:**
1. Calls `get_status` to ensure Tailscale userspace daemon is running.
2. Calls `add_serve_route` with `target: "3000"`, `servePort: 443`, `proto: "https"`, `path: "/"`.
3. Reports the secure tailnet URL (e.g. `https://my-mac.tailnet-xyz.ts.net`) with automated HTTPS.

### Example 2: Accessing a Remote Tailnet Database
**User prompt to AI assistant:**
> "I need to connect my local database client to our Postgres database on `db-cluster.ts.net:5432`."

**Assistant execution:**
1. Calls `add_remote_proxy` with `localPort: 5432`, `remoteHost: "db-cluster.ts.net"`, `remotePort: 5432`.
2. Verifies the local listener is active.
3. Instructs the user to connect to `localhost:5432`.
