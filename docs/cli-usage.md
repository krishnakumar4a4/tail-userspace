# TailUserspace CLI Reference & Usage Guide

The companion `tail-userspace` CLI provides complete scriptable control over the unprivileged daemon, inbound serve routes, outbound proxies, and environment configurations.

---

## 1. Global Syntax & Verbosity Levels

```bash
tail-userspace [command] [options]
```

### Verbosity Flags (`-v` and `-vv`)
You can pass `-v` or `-vv` to any command for troubleshooting and deep inspection:

* `-v`, `--verbose`: Displays operational steps, binary discovery paths, unix sockets, and diagnostic directories.
* `-vv`, `--debug`: Enables full debug trace, displaying raw subcommands, duration, exit codes, process standard I/O, and raw JSON status dumps.

```bash
# Check status with detailed diagnostic file paths
tail-userspace status -v

# Check status with complete raw JSON status dump
tail-userspace status -vv

# Connect with live streaming logs and verbose output
tail-userspace up -v
```

---

## 2. Daemon & Connection Commands

### `tail-userspace up [args...]`
Connects to the tailnet. If the daemon is not running, it starts it automatically. If login is required, it streams the authorization URL, automatically opens your browser, and waits up to 180 seconds for completion.

```bash
tail-userspace up

# Force re-authentication:
tail-userspace up --force-reauth
```

### `tail-userspace down`
Disconnects from the tailnet while keeping the daemon process running.

```bash
tail-userspace down
```

### `tail-userspace status [-v|-vv]`
Displays the live status of the daemon, connection state, assigned Tailscale IPs, MagicDNS domain, active Inbound Serve routes, and Outbound Remote Proxies.

```bash
tail-userspace status
```

### `tail-userspace start`
Starts the unprivileged userspace daemon (`tailscaled --tun=userspace-networking`) in the background if it is not already running.

```bash
tail-userspace start
```

### `tail-userspace stop`
Gracefully stops the userspace daemon and shuts down all active proxy forwarders.

```bash
tail-userspace stop
```

### `tail-userspace env`
Prints shell export statements configured for the active SOCKS5 and HTTP proxy ports.

```bash
# Display export statements:
tail-userspace env

# Apply to current shell session:
eval $(tail-userspace env)
```

### `tail-userspace logs`
Prints the absolute path to the active `tailscaled.log` file:

```bash
tail-userspace logs

# Stream live daemon logs in terminal:
tail -f $(tail-userspace logs)
```

---

## 3. Inbound Serve Management (`tail-userspace serve`)

Expose local web services or TCP listeners to your tailnet with automatic Let's Encrypt certificates from MagicDNS:

### Syntax
```bash
# Foreground attached mode (unmounts automatically when stopped or Ctrl+C is pressed):
tail-userspace serve [flags] <target>

# Background persistent mode (saved to config.json and runs indefinitely):
tail-userspace serve [add] --bg [flags] <target>

# Inspect live daemon serve state & discrepancies:
tail-userspace serve status [--json]

# Synchronize config.json routes to live daemon:
tail-userspace serve reapply

# Live unmount individual route or handler:
tail-userspace serve remove <target|port> [--set-path=<path>]
tail-userspace serve off [flags]

# Reset all active endpoints:
tail-userspace serve reset
```

### Supported Targets
* **Port number**: `3000`, `8080`, `5432`
* **Full HTTP/HTTPS URL**: `http://localhost:3000/api`, `http://127.0.0.1:8787`
* **Self-signed HTTPS backend**: `https+insecure://localhost:8443` (accepts invalid/self-signed upstream certificates)

### Supported Flags
* `--https=<port>`: Expose an HTTPS endpoint on your tailnet (default port: `443`).
* `--http=<port>`: Expose a plain HTTP endpoint on your tailnet (default port: `80`).
* `--tcp=<port>`: Expose raw Layer 4 TCP port forwarding.
* `--tls-terminated-tcp=<port>`: Terminate TLS and forward decrypted TCP packets upstream.
* `--set-path=<path>`: Route a specific subpath (e.g. `/api`, `/app`) to the target.
* `--proxy-protocol=<1|2>`: Send PROXY protocol v1 or v2 headers to upstream TCP services.
* `--bg`, `--background`: Persist route to `config.json` and keep running in the background.

### Examples

```bash
# 1. Foreground attached mode (displays [CLI] tag in Menu Bar App, unmounts on Ctrl+C):
tail-userspace serve 3000

# 2. Expose in background with path prefix routing:
tail-userspace serve --bg --https=443 --set-path=/api 3000

# 3. Expose self-signed HTTPS development server:
tail-userspace serve --bg https+insecure://localhost:8443

# 4. Expose raw TCP service (e.g. PostgreSQL):
tail-userspace serve --bg --tcp=5432 5432

# 5. Live unmount a specific subpath handler without resetting other routes:
tail-userspace serve --https=443 --set-path=/api off

# 6. Check live serve status and discrepancies with config:
tail-userspace serve status
tail-userspace serve status --json

# 7. Reapply all configured persistent routes to daemon:
tail-userspace serve reapply
```

---

## 4. Outbound Remote Proxy Management (`tail-userspace proxy`)

Forward a local port on your Mac to a remote tailnet machine:

### `tail-userspace proxy add <localPort> <remoteHost:remotePort> [--tls]`
Maps a local port to a remote tailnet machine.

```bash
# Standard Layer 4 TCP pass-through:
tail-userspace proxy add 9999 remote-node.tailnet-xyz.ts.net:8787

# Target port defaults to 80 if omitted:
tail-userspace proxy add 8080 remote-nas.tailnet-xyz.ts.net

# Native TLS termination mode (Upstream HTTPS -> Local plain HTTP):
tail-userspace proxy add 9443 remote-service.tailnet-xyz.ts.net:443 --tls
```

### `tail-userspace proxy list`
Lists all configured remote proxies and displays their active status and `[TLS]` tags:

```bash
tail-userspace proxy list
```

### `tail-userspace proxy remove <localPort>`
Removes a remote proxy and terminates its local listener:

```bash
tail-userspace proxy remove 9999
```

---

## 5. Diagnostic Paths & Environment Overrides

TailUserspace supports environment variable overrides for custom locations or multi-instance testing:

| Environment Variable | Default Path | Purpose |
| :--- | :--- | :--- |
| `TAIL_USERSPACE_DIR` | `~/Library/Application Support/TailUserspace` | Base directory for daemon socket, state, and `config.json`. |
| `TAIL_USERSPACE_LOGS_DIR` | `~/Library/Logs/TailUserspace` | Directory where `tailscaled.log` is written. |
| `TAILSCALED_PATH` | Discovered via `PATH` / Homebrew | Custom absolute path to the `tailscaled` binary. |
| `TAILSCALE_CLI_PATH` | Discovered via `PATH` / Homebrew | Custom absolute path to the `tailscale` CLI binary. |
