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

### Adding a Serve Route:
1. Click **Add Serve Route...** from the menu.
2. Select the protocol:
   * **HTTPS (port 443)** (Recommended: automatic Let's Encrypt certificates)
   * **HTTP (port 80)**
   * **HTTP (port 8080)**
3. Enter your **Local Port** (e.g., `3000`).
4. Enter the **Tailnet Serve Port** (defaults to 443).
5. Click **Add Route**.

### Route Context Submenu:
Each configured route displays its active status (`●` for enabled, `○` for paused). Clicking any route opens a dedicated submenu:

* **Active (Click to Pause) / Paused (Click to Enable)**: Toggle the route without deleting its configuration.
* **Open in Browser**: Opens `https://<node>.ts.net:<port><path>` in Safari/default browser.
* **Copy Tailnet URL**: Copies the public MagicDNS URL to clipboard.
* **Copy Local URL**: Copies `http://localhost:<localPort>`.
* **Edit Route...**: Opens a modal pre-filled with the route's current local port, serve port, protocol, path, and enabled state.
* **Delete Route...**: Prompts for confirmation and permanently removes the route.

---

## 4. Managing Outbound Remote Proxies (Tailnet ➔ Local)

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
