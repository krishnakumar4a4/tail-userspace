# TailUserspace for macOS

[![Build & Test](https://github.com/krishnak/tail-userspace/actions/workflows/build.yml/badge.svg)](https://github.com/krishnak/tail-userspace/actions/workflows/build.yml)
![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue)
![Architecture](https://img.shields.io/badge/arch-arm64%20%7C%20x86__64-brightgreen)
![Swift](https://img.shields.io/badge/swift-5.9%2B-orange)
![License](https://img.shields.io/badge/license-MIT-green)

A lightweight, unprivileged macOS menu bar application and shell CLI for **Tailscale in Userspace Networking Mode** (`tailscaled --tun=userspace-networking`).

Designed with UX ideas inspired by [Trayscale](https://github.com/DeedleFake/trayscale.git), built natively in Swift for macOS without any Linux GTK4 or Libadwaita dependencies.

---

## Why TailUserspace?

Standard Tailscale on macOS requires root/admin permissions, installs a system-wide Network Extension (VPN profile), and routes all device traffic through a virtual `utun` adapter.

**TailUserspace runs 100% in user space without `sudo`:**
* **Zero Root / No Admin Rights**: Runs unprivileged with isolated state in your user Library.
* **No System VPN Profile**: Does not touch your Mac's system network settings, DNS, or VPN profiles.
* **Bidirectional Port Forwarding**:
  * **Inbound (Serve)**: Expose local ports (e.g. `localhost:3000`) securely to your private tailnet via HTTPS with auto TLS.
  * **Outbound (Proxy)**: Map remote tailnet services (e.g. `remote-nas.ts.net:80`) to local ports (e.g. `localhost:8080`) via the built-in SOCKS5 forwarder.
* **Coexists with Tailscale Desktop**: Can run simultaneously alongside the official Tailscale Desktop app as an isolated secondary node on your tailnet.
* **Native & Featherweight**: **~346 KB binary**, <15 MB RAM, instant startup, zero Dock clutter (`LSUIElement = true`).

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

## Quick Start

### Prerequisites
* macOS 13.0 (Ventura) or newer (Apple Silicon or Intel).
* `tailscale` and `tailscaled` installed (e.g. via `brew install tailscale`).

### 1. Build & Package
```bash
git clone https://github.com/krishnak/tail-userspace.git
cd tail-userspace
make app
```
This builds both the CLI binary and packages the macOS menu bar bundle:
* **Menu Bar App**: `TailUserspace.app`
* **CLI Launcher**: `bin/tail-userspace`

### 2. Run the Menu Bar App
```bash
open TailUserspace.app
```
A network icon will appear in your top macOS menu bar.

---

## Menu Bar App Interface

Clicking the menu bar icon reveals the live status and interactive controls:

```
┌────────────────────────────────────────────────────────────────────────┐
│  ● Tailscale: my-mac                                        │
│  IP: 100.64.0.1  [Click to Copy]                                    │
├────────────────────────────────────────────────────────────────────────┤
│  [ Disconnect ]                                                        │
├────────────────────────────────────────────────────────────────────────┤
│  Inbound Serve (Local ➔ Tailnet)                                       │
│    ✓ localhost:8787 ➔ https://my-mac.ts.net:443/  [Copy]    │
│    [+] Add Serve Route...                                              │
├────────────────────────────────────────────────────────────────────────┤
│  Outbound Remote Proxies (Tailnet ➔ Local)                             │
│    ✓ localhost:9999 ➔ remote-node.ts.net:8787  [Click to Open]        │
│    [+] Add Remote Proxy...                                             │
├────────────────────────────────────────────────────────────────────────┤
│  SOCKS5 Proxy: 127.0.0.1:1055  [Click to Copy Shell Env]               │
│  Open Logs...                                                          │
├────────────────────────────────────────────────────────────────────────┤
│  Quit TailUserspace                                                    │
└────────────────────────────────────────────────────────────────────────┘
```

---

## CLI Command Reference

The companion `tail-userspace` CLI provides complete control from the terminal:

### Daemon & Connection
```bash
# Start userspace daemon in background
./bin/tail-userspace start

# Check live daemon PID, IPs, and active routes
./bin/tail-userspace status

# Connect / Authenticate
./bin/tail-userspace up

# Disconnect
./bin/tail-userspace down

# Gracefully stop daemon and proxy forwarders
./bin/tail-userspace stop

# Print shell export lines for SOCKS5 / HTTP proxy
eval $(./bin/tail-userspace env)
```

### Inbound Serve (Local Port ➔ Tailnet)
```bash
# Expose local port 3000 to tailnet via HTTPS (port 443)
./bin/tail-userspace serve add 3000

# Expose local port 8080 via plain HTTP on port 80
./bin/tail-userspace serve add 8080 --serve-port 80 --proto http

# List configured serve routes
./bin/tail-userspace serve list

# Remove a serve route
./bin/tail-userspace serve remove 3000

# Reset all active Tailscale Serve endpoints
./bin/tail-userspace serve reset
```

### Outbound Remote Proxy (Tailnet ➔ Localhost Port)
```bash
# Forward local port 9999 to remote-host.ts.net:8787
./bin/tail-userspace proxy add 9999 remote-host.ts.net:8787

# Forward local port 8080 to remote-nas.ts.net:80 (port defaults to 80 if omitted)
./bin/tail-userspace proxy add 8080 remote-nas.ts.net

# List active remote proxies
./bin/tail-userspace proxy list

# Remove a remote proxy
./bin/tail-userspace proxy remove 9999
```

---

## Configuration & Persistence

All routes and settings are saved to a human-readable JSON file at:  
`~/Library/Application Support/TailUserspace/config.json`

```json
{
  "autoStart": true,
  "socks5Port": 1055,
  "httpProxyPort": 1056,
  "serveRoutes": [
    {
      "id": "A6973C99-C6E9-4849-B208-9250740B3B3D",
      "localPort": 8787,
      "servePort": 443,
      "proto": "https",
      "path": "/",
      "enabled": true
    }
  ],
  "remoteProxies": [
    {
      "id": "B1234D56-E789-0123-F456-7890ABCDEF12",
      "localPort": 9999,
      "remoteHost": "remote-node.tailnet.ts.net",
      "remotePort": 8787,
      "enabled": true
    }
  ]
}
```

Whenever the daemon boots or reconnects, all enabled routes are **automatically re-applied**.

---

## Coexisting with Tailscale Desktop

If you already have the official Tailscale Desktop app installed on macOS:

* Both instances operate as **separate nodes** on your tailnet with distinct IP addresses and MagicDNS hostnames.
* Tailscale Desktop uses the system `/var/run/tailscaled.socket` and WireGuard port `41641`.
* TailUserspace uses its isolated `~/Library/Application Support/TailUserspace/tailscaled.sock` and auto-allocates an unused WireGuard port.
* Both can run at the same time without port or socket collisions.

---

## Testing & Development

```bash
# Run automated test suite (22 unit tests)
make test

# Build release binaries
make release

# Package macOS .app bundle
make app

# Clean build artifacts
make clean
```

---

## License

MIT License. See [LICENSE](LICENSE) for details.
