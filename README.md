# TailUserspace for macOS

A lightweight, unprivileged macOS menu bar application and shell CLI wrapper for **Tailscale in Userspace Networking Mode** (`tailscaled --tun=userspace-networking`).

Designed with UX ideas inspired by [Trayscale](https://github.com/DeedleFake/trayscale.git), but built natively from scratch in Swift for macOS without any Linux GTK4 or Libadwaita dependencies.

---

## Key Features

1. **100% Unprivileged (Zero Root / No `sudo`)**:
   - Runs `tailscaled` in pure userspace networking mode.
   - Requires no system extensions, no `utun` kernel device permissions, and no administrator password.
   - Completely isolated state, socket, and logs under `~/Library/Application Support/TailUserspace/`.
2. **Inbound Tailscale Serve (Local ➔ Tailnet HTTPS)**:
   - Expose any local development service (e.g. `localhost:3000`) securely to your private tailnet with automatic Let's Encrypt TLS certificates (`https://your-node.ts.net`).
3. **Outbound Remote Proxies (Tailnet ➔ Localhost Port)**:
   - Solve the key limitation of userspace networking: seamlessly map remote tailnet services (e.g. `remote-nas.ts.net:80` or `postgres.ts.net:5432`) to local ports (e.g. `localhost:8080` or `localhost:5432`) via the built-in SOCKS5 TCP bridge.
4. **Persistent Configuration**:
   - All Inbound and Outbound routes are saved to `config.json` and automatically re-applied whenever the daemon boots or reconnects.
5. **Native macOS Menu Bar App**:
   - Sits in the menu bar with dynamic status icon (`NSStatusItem`).
   - Pure accessory agent (`LSUIElement = true`) with zero Dock clutter.
   - Instant Connect/Disconnect toggles, Serve URL copying, and interactive route management.
   - Featherweight: **~350 KB binary**, <15 MB RAM, instant startup.
6. **Shell CLI Wrapper (`tail-userspace`)**:
   - Full command-line control for scripting, SSH, and headless workflows.

---

## Architecture: Bidirectional Userspace Routing

```
                          ┌────────────────────────┐
                          │   TailUserspace App    │
                          │   (macOS Menu Bar)     │
                          └───────────┬────────────┘
                                      │ Supervises (child process)
                                      ▼
                        ┌───────────────────────────┐
                        │ tailscaled                │
                        │ --tun=userspace-networking│
                        │ SOCKS5: localhost:1055    │
                        │ HTTP:   localhost:1056    │
                        │ Socket: tailscaled.sock   │
                        └───────┬───────────▲───────┘
                                │           │
         INBOUND (Feature 1)    │           │    OUTBOUND (Feature 2)
  Local Port ➔ Tailnet HTTPS    │           │    Tailnet Route ➔ Local Port
                                │           │
  tailscale serve               │           │    App listens on localhost:PORT
  (Auto Let's Encrypt TLS)      │           │    Forwards via SOCKS5 proxy (1055)
                                ▼           │
                          ═════════════════════════
                              Tailscale Tailnet
                          ═════════════════════════
```

---

## Requirements

* **macOS**: 13.0 or newer (Apple Silicon or Intel)
* **Tailscale**: `tailscaled` and `tailscale` CLI installed (e.g., via `brew install tailscale`)
* **Swift**: Swift 5.9+ (pre-installed via macOS Command Line Tools)

---

## Quick Start

### 1. Build the App & CLI
```bash
make app
```
This builds both the CLI binary and packages the macOS menu bar bundle:
* CLI: `bin/tail-userspace`
* App: `TailUserspace.app`

### 2. Launch the Menu Bar App
```bash
open TailUserspace.app
```
Look for the network icon in your macOS top menu bar.

### 3. Or Use the CLI
```bash
# Start the userspace daemon in the background
./bin/tail-userspace start

# Check status
./bin/tail-userspace status

# Connect / Log In
./bin/tail-userspace up

# Add an Inbound Serve route (exposes localhost:3000 to your tailnet via HTTPS)
./bin/tail-userspace serve add 3000

# Add an Outbound Remote Proxy (forwards localhost:8080 to remote-nas.ts.net:80)
./bin/tail-userspace proxy add 8080 remote-nas.ts.net:80

# Disconnect or stop daemon
./bin/tail-userspace stop
```

---

## CLI Command Reference

| Command | Description |
| :--- | :--- |
| `tail-userspace start` | Spawns unprivileged `tailscaled` and starts configured forwarders |
| `tail-userspace stop` | Gracefully terminates daemon and stops all forwarders |
| `tail-userspace status` | Displays daemon PID, backend state, IPs, serve routes, and proxies |
| `tail-userspace up` | Connects to the Tailscale network |
| `tail-userspace down` | Disconnects from the Tailscale network |
| `tail-userspace env` | Prints shell export commands for SOCKS5 and HTTP proxies |
| `tail-userspace logs` | Prints path to `tailscaled.log` |
| `tail-userspace serve list` | Lists all configured Inbound Serve routes |
| `tail-userspace serve add <port>` | Exposes local port to tailnet HTTPS and persists to `config.json` |
| `tail-userspace serve remove <port>`| Removes an Inbound Serve route |
| `tail-userspace serve reset` | Resets live `tailscale serve` endpoints |
| `tail-userspace proxy list` | Lists all configured Outbound Remote Proxies |
| `tail-userspace proxy add <localPort> <host:port>` | Forwards a local port to a remote tailnet service |
| `tail-userspace proxy remove <localPort>` | Removes an Outbound Remote Proxy |

---

## Proxy Environment Configuration

Because userspace networking does not create a kernel virtual interface, you can route terminal commands through Tailscale using the built-in SOCKS5 or HTTP proxy:

```bash
eval $(./bin/tail-userspace env)
# Sets:
# export ALL_PROXY=socks5://127.0.0.1:1055
# export HTTP_PROXY=http://127.0.0.1:1056
# export HTTPS_PROXY=http://127.0.0.1:1056

curl http://other-machine.ts.net/
```

Or simply use **Outbound Remote Proxies** to map the service directly to `localhost:<port>`!

---

## Persistent Configuration File

Configuration is stored in human-readable JSON at:  
`~/Library/Application Support/TailUserspace/config.json`

```json
{
  "autoStart": true,
  "socks5Port": 1055,
  "httpProxyPort": 1056,
  "serveRoutes": [
    {
      "id": "1A2B3C",
      "localPort": 3000,
      "servePort": 443,
      "proto": "https",
      "path": "/",
      "enabled": true
    }
  ],
  "remoteProxies": [
    {
      "id": "4D5E6F",
      "localPort": 8080,
      "remoteHost": "nas.tailnet.ts.net",
      "remotePort": 80,
      "enabled": true
    }
  ]
}
```

---

## Development & Testing

```bash
# Run test suite
make test

# Clean build artifacts
make clean
```
