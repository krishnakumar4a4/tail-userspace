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
  * **Outbound (Proxy)**: Map remote tailnet services (e.g. `remote-nas.ts.net:80`) to local ports (e.g. `localhost:8080`) via the built-in SOCKS5 forwarder with optional native TLS termination (`--tls`).
* **Coexists with Tailscale Desktop**: Can run simultaneously alongside the official Tailscale Desktop app as an isolated secondary node on your tailnet.
* **Native & Featherweight**: **~398 KB bundle**, <15 MB RAM, instant startup, zero Dock clutter (`LSUIElement = true`).

---

## Menu Bar Application

TailUserspace lives quietly in your macOS menu bar, providing real-time status and interactive controls:

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

### Authenticating via Menu Bar
1. Click the status bar icon and choose **Connect** (or press `⌘C`).
2. If login is required, the menu highlights **▲ Tailscale: Login Required**.
3. Click **Log In with Browser...** (or press `⌘L`) to automatically open Tailscale's authorization page in your default browser.
4. Once authenticated, the menu bar icon turns green (`●`) and displays your node name, Tailscale IP, and MagicDNS domain.

### Key Menu Bar Features
* **Instant CLI ↔ GUI Sync**: CLI changes (e.g. `proxy remove`, `proxy add`) are detected immediately on disk, refreshing the menu and forwarders the instant you click the icon.
* **Interactive Route Management**: Every Inbound Serve route and Outbound Remote Proxy includes options to **Pause / Resume**, **Edit Route/Proxy**, and **Delete**.
* **Configuration Viewer**: Inspect raw JSON directly using **"View Configuration in App..."** or open `config.json` in your default code editor.

👉 For complete walkthroughs, submenus, and dialog options, see the **[Menu Bar Application Usage Guide](docs/menubar-app.md)**.

---

## Command-Line Interface (CLI)

The companion `tail-userspace` CLI allows complete terminal management and headless automation:

### Authenticating via CLI
Running `tail-userspace up` connects to the tailnet. If authorization is needed, it extracts the login URL, automatically launches your browser, and waits for authentication to complete:

```bash
tail-userspace up
```

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

### Core CLI Commands

| Command | Description |
| :--- | :--- |
| `tail-userspace up` | Connects to tailnet with automated browser login flow |
| `tail-userspace down` | Disconnects from tailnet |
| `tail-userspace status` | Displays daemon PID, connection state, IPs, and routes |
| `tail-userspace start` | Starts unprivileged daemon in background |
| `tail-userspace stop` | Shuts down daemon and all proxy listeners |
| `eval $(tail-userspace env)` | Exports `ALL_PROXY` variables to your current shell session |
| `tail-userspace serve add <port>` | Exposes local port to tailnet via HTTPS (port 443) |
| `tail-userspace serve list` | Lists all configured inbound serve routes |
| `tail-userspace serve remove <port>` | Removes an inbound serve route |
| `tail-userspace proxy add <local> <target> [--tls]` | Forwards local port to remote tailnet service (with optional TLS termination) |
| `tail-userspace proxy list` | Lists all active outbound remote proxies |
| `tail-userspace proxy remove <local>` | Removes an outbound proxy and frees the local port |
| `tail-userspace logs` | Prints absolute path to `tailscaled.log` |

### Verbosity Flags (`-v` and `-vv`)
Pass `-v` (verbose diagnostics) or `-vv` (full debug trace with raw JSON dumps and process standard I/O) to any command:

```bash
tail-userspace status -v
tail-userspace up -vv
```

👉 For complete command syntax, advanced flags, and scripting examples, see the **[CLI Reference & Usage Guide](docs/cli-usage.md)**.

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

### Recommended: Install Pre-Built Release

1. Download `TailUserspace-macOS.zip` from GitHub Releases or Actions Artifacts.
2. Extract and move `TailUserspace.app` to your Applications folder:
   ```bash
   unzip TailUserspace-macOS.zip
   mv TailUserspace.app /Applications/
   ```
3. **Clear Gatekeeper Quarantine Flag**:
   Since the binary is ad-hoc signed, remove the macOS browser quarantine flag:
   ```bash
   xattr -cr /Applications/TailUserspace.app
   ```
4. *(Optional)* Install the CLI globally:
   ```bash
   mkdir -p ~/.local/bin && cp tail-userspace-cli ~/.local/bin/tail-userspace
   ```
5. Launch the Menu Bar App:
   ```bash
   open /Applications/TailUserspace.app
   ```

👉 To compile from source instead, see **[Building from Source (Method B)](docs/installation-and-maintenance.md#1-building-from-source-method-b)**.

---

## Configuration & Persistence

All routes, forwarders, and settings are saved atomically to:  
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
      "localPort": 9443,
      "remoteHost": "remote-node.tailnet.ts.net",
      "remotePort": 443,
      "terminateTLS": true,
      "enabled": true
    }
  ]
}
```

Whenever the daemon starts or reconnects, all enabled routes are **automatically restored and re-applied**.

---

## Architecture

TailUserspace operates with an unprivileged process model that isolates WireGuard tunnels, state files, and UNIX sockets inside your user session without root permissions.

👉 For detailed architecture diagrams, bidirectional traffic flows, TLS termination mechanics, and cache coherency design, see **[TailUserspace Architecture](docs/architecture.md)**.

---

## Maintenance & Development

* **[How to Update](docs/installation-and-maintenance.md#2-updating-tailuserspace)**: Upgrade steps preserving your tailnet credentials and routes.
* **[Clean Uninstallation](docs/installation-and-maintenance.md#3-clean-uninstallation)**: Complete removal of binaries, sockets, and configuration.
* **[Development & Testing](docs/installation-and-maintenance.md#4-development--testing-workflow)**: Running the test suite (`make test`) and packaging (`make dist`).

---

## License

MIT License. See [LICENSE](LICENSE) for details.
