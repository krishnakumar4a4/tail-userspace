# Installation, Maintenance & Development Guide

This document details source compilation, updates, uninstallation, and development workflows for **TailUserspace**.

---

## 1. Building from Source (Method B)

If you prefer building from source rather than downloading pre-built releases:

### Requirements
* macOS 13.0+ (Ventura, Sonoma, Sequoia)
* Xcode Command Line Tools (`xcode-select --install`)
* Swift 5.9+ toolchain
* Tailscale (`brew install tailscale`)

### Build Steps
```bash
# 1. Clone repository
git clone https://github.com/krishnakumar4a4/tail-userspace.git
cd tail-userspace

# 2. Build and package the signed app bundle and CLI
make dist

# 3. Launch the app
open TailUserspace.app
```

### A Note on App Bundle Size:
On macOS APFS filesystems, running `ls -ld TailUserspace.app` displays `96` bytes. In Unix/macOS, `96` is simply the inode directory table size for a folder containing 3 entries. The actual compiled application size is **~365 KB - 398 KB**, which can be verified with:

```bash
du -sh TailUserspace.app
```

---

## 2. Updating TailUserspace

When a new version is released:

### Step 1: Stop the running instance
```bash
tail-userspace stop
# Or select 'Quit TailUserspace' (⌘Q) from the menu bar
```

### Step 2: Replace binaries

#### If updating from pre-built release:
```bash
unzip TailUserspace-macOS.zip
mv TailUserspace.app /Applications/
xattr -cr /Applications/TailUserspace.app
sudo cp tail-userspace-cli /usr/local/bin/tail-userspace
```

#### If updating from source:
```bash
git pull origin main
make dist
cp -R TailUserspace.app /Applications/
```

### Step 3: Restart the app
```bash
open /Applications/TailUserspace.app
```

> **Data Preservation**: Your tailnet authentication credentials, node encryption keys (`tailscaled.state`), and configured routes (`config.json`) reside in `~/Library/Application Support/TailUserspace/` and remain completely untouched across updates.

---

## 3. Clean Uninstallation

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

## 4. Development & Testing Workflow

The project uses a standard Swift Package Manager structure with a Makefile driver:

```bash
# Run unit and regression test suite
make test

# Compile release binaries
make release

# Package verified macOS .app bundle and distribution zip
make dist

# Clean build artifacts
make clean
```
