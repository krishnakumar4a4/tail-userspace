# TailUserspace for macOS

[![Build & Test](https://github.com/krishnakumar4a4/tail-userspace/actions/workflows/build.yml/badge.svg)](https://github.com/krishnakumar4a4/tail-userspace/actions/workflows/build.yml)
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
* **Native & Featherweight**: **~365 KB bundle**, <15 MB RAM, instant startup, zero Dock clutter (`LSUIElement = true`).

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

## Installation & Setup

### Prerequisites
TailUserspace utilizes the official open-source Tailscale engine in userspace mode. On any fresh Mac, ensure Tailscale is installed:

```bash
# Install Tailscale engine via Homebrew
brew install tailscale
```

> **Note**: You do **not** need to run `sudo brew services start tailscale`. TailUserspace supervises its own unprivileged child daemon process automatically.

---

### Method A: Install from GitHub Actions / Pre-built Release (Recommended)

1. Download `TailUserspace-macOS` from the GitHub Actions Artifacts or Release page.
2. Extract the archive:
   ```bash
   unzip TailUserspace-macOS.zip
   ```
3. Move `TailUserspace.app` to your Applications folder:
   ```bash
   mv TailUserspace.app /Applications/
   ```
4. **Clear Gatekeeper Quarantine Attribute**:
   Since the app is open-source and ad-hoc signed, macOS attaches a quarantine flag to browser downloads. Remove it so macOS allows it to launch:
   ```bash
   xattr -cr /Applications/TailUserspace.app
   ```
5. *(Optional)* Install the CLI globally:
   ```bash
   sudo cp tail-userspace-cli /usr/local/bin/tail-userspace
   # Or install to your user bin directory without sudo:
   mkdir -p ~/.local/bin && cp tail-userspace-cli ~/.local/bin/tail-userspace
   ```
6. Launch the Menu Bar App:
   ```bash
   open /Applications/TailUserspace.app
   ```

---

### Method B: Build from Source

```bash
# 1. Clone repository
git clone https://github.com/krishnakumar4a4/tail-userspace.git
cd tail-userspace

# 2. Build and package the signed app bundle and CLI
make dist

# 3. Launch the app
open TailUserspace.app
```

> **A Note on Bundle Size**:
> On macOS APFS filesystems, running `ls -ld TailUserspace.app` displays `96` bytes. In Unix/macOS, `96` is simply the inode directory table size for a folder containing 3 entries. The actual compiled application size is **~365 KB**, which can be verified with `du -sh TailUserspace.app`.

---

## Authenticating & Connecting

### Option 1: Via CLI (`tail-userspace up`)
Running `up` starts the daemon (if not already running), detects whether authentication is needed, automatically launches your default browser to the Tailscale login page, and waits for authentication to complete:

```bash
tail-userspace up
```

Output:
```text
Connecting to Tailscale network...

============================================================================
  Tailscale Authentication Required
  👉 https://login.tailscale.com/a/0123456789abcdef
============================================================================
  Opening URL in your default browser...
  Waiting for authentication in browser... (Press Ctrl+C to cancel)

✓ Connected to Tailscale network!
  Node DNS:   my-mac.tailnet-xyz.ts.net
  Tailnet IP: 100.64.0.1
```

### Option 2: Via Menu Bar
Click the network icon in your macOS menu bar and click **Connect**. If your node needs authentication, it automatically opens your web browser to approve the login.

---

## CLI Command Reference

The companion `tail-userspace` CLI provides complete control from the terminal:

### Verbosity Levels (`-v` and `-vv`)
You can pass `-v` or `-vv` to any command for troubleshooting and deep inspection:

* `-v`, `--verbose`: Displays execution steps, binary discovery paths, unix sockets, and diagnostic directories.
* `-vv`, `--debug`: Enables full debug trace, displaying raw subcommands, duration, exit codes, process standard I/O, and raw JSON status dumps.

```bash
# Check status with detailed file paths
tail-userspace status -v

# Check status with complete raw JSON status dump
tail-userspace status -vv

# Connect with live streaming logs
tail-userspace up -v
```

---

### Daemon & Connection Commands
```bash
# Start userspace daemon in background
tail-userspace start

# Check live daemon PID, IPs, and active routes
tail-userspace status

# Connect / Authenticate (with auto browser opening)
tail-userspace up

# Disconnect from tailnet
tail-userspace down

# Gracefully stop daemon and proxy forwarders
tail-userspace stop

# Print shell export lines for SOCKS5 / HTTP proxy
eval $(tail-userspace env)

# Print path to tailscaled log file
tail-userspace logs
```

---

### Inbound Serve (Local Port ➔ Tailnet)
Expose local development servers or services to your tailnet over HTTPS with automatic Let's Encrypt certificates:

```bash
# Expose local port 3000 to tailnet via HTTPS (port 443)
tail-userspace serve add 3000

# Expose local port 8080 via plain HTTP on port 80
tail-userspace serve add 8080 --serve-port 80 --proto http

# List configured serve routes
tail-userspace serve list

# Remove a serve route
tail-userspace serve remove 3000

# Reset all active Tailscale Serve endpoints
tail-userspace serve reset
```

---

### Outbound Remote Proxy (Tailnet ➔ Localhost Port)
Map a remote tailnet machine's port directly to a local port on your Mac using the unprivileged SOCKS5 forwarder:

```bash
# Forward local port 9999 to remote-host.ts.net:8787 (raw TCP pass-through)
tail-userspace proxy add 9999 remote-host.ts.net:8787

# Forward local port 8080 to remote-nas.ts.net:80 (port defaults to 80 if omitted)
tail-userspace proxy add 8080 remote-nas.ts.net

# Forward local port 9443 to remote HTTPS endpoint with automatic TLS termination:
# Connects to remote-service.ts.net:443 via HTTPS over SOCKS5, terminates TLS natively
# with Apple Keychain / Let's Encrypt validation, and serves plain HTTP to localhost.
tail-userspace proxy add 9443 remote-service.ts.net:443 --tls

# Now your local application or curl can talk directly without SNI or certificate mismatch:
curl http://localhost:9443/api/v1/status

# List active remote proxies (shows [TLS] badge for terminated endpoints)
tail-userspace proxy list

# Remove a remote proxy
tail-userspace proxy remove 9999
```

> [!TIP]
> In the Menu Bar App, clicking **"Add Outbound Proxy..."** presents a checkbox: **"Terminate remote TLS (upstream HTTPS -> local HTTP)"** allowing one-click configuration of TLS reverse proxies.

---

## Menu Bar App Interface

Clicking the menu bar icon reveals live status, interactive controls, and real-time route management:

```text
┌────────────────────────────────────────────────────────────────────────┐
│  ● Tailscale: my-mac                                                   │
│  IP: 100.64.0.1                     (Click to copy IP)                 │
│  Domain: my-mac.tailnet-xyz.ts.net  (Click to copy domain)             │
├────────────────────────────────────────────────────────────────────────┤
│  Disconnect                                                         ⌘D │
│  Re-authenticate...                                                    │
├────────────────────────────────────────────────────────────────────────┤
│  INBOUND SERVE (LOCAL ➔ TAILNET)                                       │
│    ● localhost:8787 ➔ https://:443/  ▶  [ Submenu:                     │
│                                           • Active / Pause             │
│                                           • Open in Browser            │
│                                           • Copy Tailnet URL           │
│                                           • Copy Local URL             │
│                                           • Edit Route...              │
│                                           • Delete Route... ]          │
│    [+] Add Serve Route...                                              │
├────────────────────────────────────────────────────────────────────────┤
│  OUTBOUND REMOTE PROXIES (TAILNET ➔ LOCAL)                             │
│    ● localhost:9443 ➔ remote-node.ts.net:443 [TLS] ▶ [ Submenu:        │
│                                           • Active / Pause             │
│                                           • Open Local Endpoint        │
│                                           • Copy Local / Remote URL    │
│                                           • Edit Proxy...              │
│                                           • Delete Proxy... ]          │
│    [+] Add Outbound Proxy...                                           │
├────────────────────────────────────────────────────────────────────────┤
│  USERSPACE PROXIES & SHELL ENVIRONMENT                                 │
│  SOCKS5 Proxy: 127.0.0.1:1055       (Click to copy address)            │
│  HTTP Proxy: 127.0.0.1:1056         (Click to copy address)            │
│  Copy Shell Export (ALL_PROXY)                                         │
├────────────────────────────────────────────────────────────────────────┤
│  CONFIGURATION & DIAGNOSTICS                                           │
│  Open Configuration File (config.json)                                 │
│  View Configuration in App...                                          │
│  Reveal Data Directory in Finder                                       │
│  View Daemon Logs (tailscaled.log)                                     │
│  Reset Tailscale Serve...                                              │
├────────────────────────────────────────────────────────────────────────┤
│  Tailscale Userspace v1.0 (Darwin)                                     │
│  Quit TailUserspace                                                 ⌘Q │
└────────────────────────────────────────────────────────────────────────┘
```

### Real-Time Synchronization & Route Controls
* **Instant CLI ↔ GUI Sync**: Changes made via CLI (`tail-userspace proxy remove`, `tail-userspace proxy add`, etc.) are detected instantly via file modification timestamps and `NSMenuDelegate`, immediately refreshing the UI and forwarders whenever the menu is clicked.
* **Edit & Delete from UI**: Every inbound serve route and outbound remote proxy contains a dedicated submenu with one-click options to **Edit Route / Proxy** (with pre-filled parameters), **Delete Route / Proxy**, or **Pause / Resume** traffic.
* **Built-in Configuration Viewer**: Inspect raw JSON directly within the app using **"View Configuration in App..."** or open in your default editor with **"Open Configuration File"**.

---

## Configuration & Persistence

All routes, forwarders, and settings are saved to:  
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

Whenever the daemon starts or reconnects, all enabled routes are **automatically re-applied**.

---

## How to Update

When a new version is released:

1. **Stop the running instance**:
   ```bash
   tail-userspace stop
   # Or select 'Quit TailUserspace' from the menu bar
   ```
2. **Replace the binaries**:
   - If using pre-built release:
     ```bash
     mv TailUserspace.app /Applications/
     xattr -cr /Applications/TailUserspace.app
     sudo cp tail-userspace-cli /usr/local/bin/tail-userspace
     ```
   - If building from source:
     ```bash
     git pull
     make dist
     cp -R TailUserspace.app /Applications/
     ```
3. **Restart the app**:
   ```bash
   open /Applications/TailUserspace.app
   ```

> **Data Preservation**: Your tailnet authentication credentials, node encryption keys (`tailscaled.state`), and configured routes (`config.json`) reside in `~/Library/Application Support/TailUserspace/` and remain completely untouched across updates.

---

## Clean Uninstallation

To completely remove TailUserspace and all associated data from your Mac:

```bash
# 1. Disconnect and shut down running daemon and proxies
tail-userspace down
tail-userspace stop

# 2. Remove the Application and CLI binaries
rm -rf /Applications/TailUserspace.app
sudo rm -f /usr/local/bin/tail-userspace
rm -f ~/.local/bin/tail-userspace

# 3. Remove all state, credentials, configurations, and logs
rm -rf ~/Library/Application\ Support/TailUserspace
rm -rf ~/Library/Logs/TailUserspace
```

---

## Testing & Development

```bash
# Run automated test suite (24 unit tests)
make test

# Build release binaries
make release

# Package verified macOS .app bundle and distribution archive
make dist

# Clean build artifacts
make clean
```

---

## License

MIT License. See [LICENSE](LICENSE) for details.
