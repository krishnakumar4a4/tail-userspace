# TailUserspace Architecture

This document details the internal architecture, process model, and bidirectional networking design of **TailUserspace for macOS**.

---

## 1. High-Level Process Model

Standard Tailscale on macOS requires root privileges (`sudo`), installs a system-wide Network Extension (VPN profile), and configures a virtual `utun` network adapter that intercepts all system traffic.

In contrast, TailUserspace runs **100% in user space without `sudo`**:

```
┌────────────────────────────────────────────────────────┐
│                   macOS User Session                   │
├───────────────────────────┬────────────────────────────┤
│   TailUserspace.app       │    tail-userspace CLI      │
│   (AppKit Menu Bar UI)    │    (Swift Terminal Tool)   │
└─────────────┬─────────────┴──────────────┬─────────────┘
              │ Supervises child process   │ Interacts via UNIX socket
              ▼                            ▼
┌────────────────────────────────────────────────────────┐
│ tailscaled --tun=userspace-networking                  │
│                                                        │
│ • State Path:   ~/Library/Application Support/         │
│                 TailUserspace/tailscaled.state         │
│ • Socket:       tailscaled.sock                        │
│ • SOCKS5 Proxy: 127.0.0.1:1055                         │
│ • HTTP Proxy:   127.0.0.1:1056                         │
└───────────────────────────┬────────────────────────────┘
                            │ WireGuard Encrypted UDP
                            ▼
              ═════════════════════════════
                    Tailscale Tailnet
              ═════════════════════════════
```

### Key Isolation Characteristics:
1. **Unprivileged Daemon**: The `tailscaled` daemon runs with your standard macOS user credentials. No root passwords or sudo prompts are ever required.
2. **Dedicated Storage Directory**: State files, runtime sockets, and configuration are isolated in `~/Library/Application Support/TailUserspace/`.
3. **No System Network Disruption**: System DNS, routing tables, and network interfaces remain completely untouched.
4. **Desktop Coexistence**: Can run simultaneously alongside the official Tailscale Desktop app as an independent, secondary node on your tailnet.

---

## 2. Bidirectional Userspace Routing

Userspace networking bridges traffic between your Mac and remote tailnet nodes using two distinct directional mechanisms:

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
         INBOUND ROUTING        │           │    OUTBOUND ROUTING
   Local Port ➔ Tailnet HTTPS   │           │    Tailnet Route ➔ Local Port
                                │           │
   tailscale serve              │           │    App listens on localhost:PORT
   (Auto Let's Encrypt TLS)     │           │    Forwards via SOCKS5 proxy (1055)
                                ▼           │
                          ═════════════════════════
                              Tailscale Tailnet
                          ═════════════════════════
```

### Inbound Serve (Local Port ➔ Tailnet)
* Exposes local web services (e.g. `localhost:3000` or `localhost:8080`) to other nodes on your private tailnet.
* Leverages Tailscale's built-in `serve` feature (`tailscale serve --bg`).
* Automatic HTTPS with automated Let's Encrypt certificates managed by MagicDNS (e.g. `https://my-mac.tailnet-xyz.ts.net:443`).

### Outbound Remote Proxy (Tailnet ➔ Localhost Port)
* Maps remote tailnet services (e.g. `remote-nas.ts.net:80` or `db-node.ts.net:5432`) to local listening ports on your Mac (e.g. `localhost:8080`).
* Implemented via `SOCKS5Forwarder.swift`, a lightweight, multi-client asynchronous forwarder.
* When a local connection arrives at `127.0.0.1:<localPort>`, the forwarder negotiates a connection with `tailscaled`'s local SOCKS5 proxy (`127.0.0.1:1055`), establishing an end-to-end TCP stream to the destination.

---

## 3. Native TLS Termination Reverse Proxy Engine (`--tls`)

When forwarding to remote HTTPS services on your tailnet, standard Layer 4 TCP forwarding can trigger TLS certificate and SNI validation errors if clients connect directly to `localhost:<port>`.

To resolve this without external dependencies, TailUserspace includes a built-in reverse proxy mode:

```
┌────────────────────────────────────────────────────────────────────────┐
│                   Outbound TLS Termination Engine                      │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│   Local Client (curl / browser / app)                                  │
│          │ Plain HTTP request (http://localhost:9443/api)              │
│          ▼                                                             │
│   SOCKS5Forwarder (Local Port 9443)                                    │
│   [Native Reverse Proxy via Foundation URLSession]                     │
│          │                                                             │
│          │ Upstream HTTPS via SOCKS5 (127.0.0.1:1055)                  │
│          │ Native TLS 1.3 + SNI + Apple Keychain Trust Validation      │
│          ▼                                                             │
│   Remote Tailnet Node (https://remote-node.ts.net:443)                 │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

### Highlights:
* **Zero External Dependencies**: Built entirely with Swift Foundation (`URLSessionConfiguration.ephemeral` configured with `kCFNetworkProxiesSOCKSProxy`).
* **Automatic SNI & Cert Validation**: Sets upstream SNI to the target hostname and validates Let's Encrypt certificates against macOS system keychain roots.
* **Seamless Local Consumption**: Local tools and internal scripts communicate over plain HTTP to `localhost:<port>` without disabling TLS verification or configuring custom CA certificates.

---

## 4. Multi-Process Cache Coherency Architecture

Both the Menu Bar App and the CLI operate as separate processes reading and writing the shared `config.json`.

```
┌────────────────────────────┐         ┌───────────────────────────┐
│   CLI Process (Terminal)   │         │    AppKit Menu Bar App    │
└─────────────┬──────────────┘         └─────────────┬─────────────┘
              │                                      │
              │ `proxy remove 9999`                  │ User clicks Menu Bar Icon
              ▼                                      ▼
      Writes `config.json`                 `NSMenuDelegate.menuWillOpen()`
  (Updated modificationDate)                         │
              │                                      ▼
              └─────────────────────────────▶ Checks file modificationDate
                                              (Mtime changed! Evicts cache)
                                                     │
                                                     ▼
                                              Re-reads `config.json`
                                              Stops forwarder on :9999
                                              Rebuilds UI with 0ms latency
```

* **Filesystem Timestamp Invalidation**: `ConfigManager.load()` checks `FileManager.default.attributesOfItem(atPath: configPath)[.modificationDate]`. If the timestamp differs from `lastModifiedDate`, the in-memory cache is atomically evicted.
* **Instant Event-Driven Sync**: `AppDelegate` implements `NSMenuDelegate`. The moment a user clicks the status item, `menuWillOpen` forces a config reload and forwarder reconciliation before the menu renders.
