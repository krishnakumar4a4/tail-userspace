# Menu Bar Application Usage Guide

This guide provides a comprehensive overview of the **TailUserspace Menu Bar Application** (`TailUserspace.app`) for macOS.

---

## 1. Overview & Status Bar Item

TailUserspace lives quietly in your macOS menu bar without Dock clutter (`LSUIElement = true`). Its icon dynamically reflects the daemon's connection state and active routes:

| Status Icon | Meaning | Description |
| :--- | :--- | :--- |
| `network` | **Online** | Connected to your tailnet. |
| `network.badge.shield.half.filled` | **Online + Active Routes** | Connected with active Serve routes or Remote Proxies. |
| `network.slash` | **Disconnected** | Userspace daemon process is running, but tailnet connection is down. |
| `xmark.circle` | **Stopped** | Unprivileged `tailscaled` daemon is not currently running. |
| `[CLI]` Badge | **Ephemeral CLI Session** | Displayed next to the status icon whenever a foreground terminal session (`tail-userspace serve <target>`) is running attached. Disappears automatically when the CLI stops. |

---

## 2. Connecting & Authenticating

1. Click the status bar icon to open the menu.
2. If the daemon is not running, click **Start Userspace Daemon**.
3. Click **Connect** (or press `⌘C`).
4. If your node requires authentication:
   * The app detects the `NeedsLogin` state and displays **▲ Tailscale: Login Required**.
   * Click **Log In with Browser...** (or press `⌘L`).
   * Your default web browser opens directly to Tailscale's authorization URL.
5. Once authenticated, the icon updates to `network` (or `network.badge.shield.half.filled`), and the header shows:
   * **● Tailscale: \<NodeName\>**
   * **IP: 100.x.y.z** (Clicking copies the IP to your clipboard)
   * **Domain: \<node\>.ts.net** (Clicking copies the MagicDNS domain)

---

## 3. Managing Inbound Serve Routes (Local ➔ Tailnet)

Inbound serve exposes a local service running on your Mac (e.g., a local development server on port 3000) to other machines on your tailnet with automatic HTTPS.

### Modern Add & Edit Dialogs
The app features modern, descriptive dialogs with clear explanations:
* **Local Target Service**: Supports port numbers (`3000`), full URLs (`http://localhost:3000/api`), and self-signed HTTPS backends (`https+insecure://localhost:8443`).
* **Tailnet Protocol & Port**:
  * **HTTPS (Port 443)** (Recommended: automatic Let's Encrypt certificates from MagicDNS)
  * **HTTP (Port 80)** (Plain web forwarding)
  * **HTTP Alternate (Port 8080)**
  * **TCP Passthrough** (Raw Layer 4 TCP forwarding)
  * **TLS-Terminated TCP** (Terminates TLS, forwards decrypted plain TCP)
* **Tailnet Path Prefix (`--set-path`)**: Allows mounting multiple web services on the same domain under different paths (e.g., `/` or `/api`).
* **Informative Architecture Card**: Explains how Tailscale Serve secures and routes inbound traffic.

### Discrepancy & Ephemeral Indicators
The menu actively inspects live daemon state against `config.json`:
* `● <target>`: Route active and in sync with the live daemon.
* `⚠️ <target> (Not on daemon)`: Route is enabled in `config.json` but not running on the live daemon. Clicking provides a **Reapply to Live Daemon** action.
* `🔄 <target> (Target mismatch)`: Live daemon target differs from `config.json`.
* `⚡ [CLI] <target>`: Ephemeral foreground session started from the CLI. Displays process PID and provides a **Stop CLI Session** button.
* `ℹ️ [Daemon] <target>`: Live route running on the daemon but unmanaged in `config.json`. Provides **Save to Config** or **Turn Off on Daemon**.

### Route Context Submenu:
Each configured route displays its active status. Clicking opens its submenu:
* **Active (Click to Pause) / Paused (Click to Enable)**: Toggling off unmounts the live handler from the daemon immediately; toggling on reapplies it.
* **Open in Browser**: Opens the route in Safari/default browser.
* **Copy Tailnet URL**: Copies the MagicDNS URL to clipboard.
* **Copy Local Target**: Copies the local port or target URL.
* **Edit Route...**: Opens a modern dialog pre-filled with all settings.
* **Delete Route...**: Prompts for confirmation and live-unmounts the route from the daemon before removing it from configuration.

---

## 4. Managing Outbound Remote Proxies (Local ← Tailnet)

Outbound remote proxies forward a local port on your Mac to a remote service on your tailnet using unprivileged SOCKS5 forwarding.

### Adding a Remote Proxy:
1. Click **Add Outbound Proxy...**.
2. Enter the **Local Port** to listen on (e.g., `9443` or `8080`).
3. Enter the **Remote Host / IP** (e.g., `nas.tailnet-xyz.ts.net`).
4. Enter the **Remote Target Port** (e.g., `443` or `80`).
5. *(Optional)* Check **"Terminate remote TLS (upstream HTTPS -> local HTTP)"**:
   * When enabled, TailUserspace terminates the upstream TLS certificate natively using Apple's trust store.
   * You can access the remote HTTPS service locally via plain HTTP (`http://localhost:<localPort>`), avoiding certificate hostname mismatches or client SNI issues.
6. Click **Add Proxy**.

### Proxy Context Submenu:
* **Active / Paused**: Toggle the local TCP listener on or off.
* **Open Local Endpoint**: Opens `http://localhost:<localPort>` in your browser.
* **Copy Local URL**: Copies `http://localhost:<localPort>`.
* **Copy Target Endpoint**: Copies `<remoteHost>:<remotePort>`.
* **Edit Proxy...**: Modify ports, target hostname, or TLS termination state.
* **Delete Proxy...**: Immediately shuts down the local listener and removes the proxy entry.

---

## 5. Userspace Proxies & Environment

TailUserspace maintains unprivileged SOCKS5 and HTTP proxy listeners:
* **SOCKS5 Proxy (127.0.0.1:1055)**: Click to copy the socket address.
* **HTTP Proxy (127.0.0.1:1056)**: Click to copy the socket address.
* **Copy Shell Export (ALL_PROXY)**: Copies `export ALL_PROXY=socks5://127.0.0.1:1055` for instant terminal session proxying.

---

## 6. Configuration & System Diagnostics

Under the **Configuration & Diagnostics** section:

1. **Open Configuration File (config.json)**: Opens `~/Library/Application Support/TailUserspace/config.json` in your default code/text editor.
2. **View Configuration in App...**: Displays a modal with a scrolling, monospaced view of the current JSON configuration. Includes **Copy JSON** and **Open in External Editor** buttons.
3. **Reveal Data Directory in Finder**: Opens the application support directory containing `tailscaled.state`, `tailscaled.sock`, and `config.json`.
4. **View Daemon Logs (tailscaled.log)**: Opens the live daemon log file located in `~/Library/Logs/TailUserspace/`.
5. **Reset Tailscale Serve...**: Clears active serve configurations on the live daemon.
