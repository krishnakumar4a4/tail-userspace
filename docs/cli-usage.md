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

Expose local web services to your tailnet via HTTPS (with automatic Let's Encrypt certificates):

### `tail-userspace serve add <localPort> [--serve-port <port>] [--proto <http|https|tcp>]`
Adds an inbound serve route. Automatically applied immediately if online, or queued for when the daemon starts.

```bash
# Expose local port 3000 to tailnet via HTTPS on port 443 (default)
tail-userspace serve add 3000

# Expose local port 8080 via plain HTTP on port 80
tail-userspace serve add 8080 --serve-port 80 --proto http
```

### `tail-userspace serve list`
Lists all configured inbound serve routes:

```bash
tail-userspace serve list
```

### `tail-userspace serve remove <localPort>`
Removes an existing serve route for a given local port:

```bash
tail-userspace serve remove 3000
```

### `tail-userspace serve reset`
Resets all active Tailscale Serve endpoints on the live daemon:

```bash
tail-userspace serve reset
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
