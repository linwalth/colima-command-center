# Colima Command Center

A macOS menu bar app for managing local Colima VMs, Docker, and k3s workloads.
All operations are implemented natively in Swift — no external shell scripts.

## What It Does

Colima Command Center sits in your menu bar and gives you a single-window
dashboard for your local Kubernetes development environment:

- **Start/stop the Colima VM** with explicit buttons (no guesswork toggle)
- **Live monitoring** of CPU, RAM, disk usage, and load averages
- **Docker status** with gentle, safe cleanup
- **Kubernetes resource browser** for deployments, pods, nodes, services, PVCs
- **Configuration editor** for `colima.yaml` with a k3s version picker
- **Automatic app scaling** on startup/shutdown (configure via `apps.json`)

## Features

### Menu Bar
- **Status icon** (shipping box) with live running/stopped state, 5s polling
- **Explicit start/stop actions** — the button does exactly what its label says,
  never guesses VM state
- **Multi-profile support** via `COLIMA_PROFILE` environment variable

### Status Tab (Live Dashboard)
Three sub-tabs with automatic 5-second refresh:

#### Colima VM
- Animated status indicator (pulsing ring)
- **Circular gauges**: CPU %, RAM %, Data Disk % (color-coded green/yellow/red)
- **Linear progress bars**: Data Disk, Root Disk
- **Load average graph**: 3-line sparkline (1m blue / 5m purple / 15m orange)
  with a dashed reference line at full CPU utilization
- Runtime, address, architecture, CPU cores

#### Docker
- Daemon status (active/inactive + running container count)
- Docker storage breakdown (`docker system df` table)
- **Gentle cleanup**: removes only exited containers, untagged (dangling)
  images, and unused build cache — never touches running containers or tagged
  images

#### Kubernetes
- Collapsible sections for Deployments, Pods, Nodes, Services, PVCs, Flux CD,
  and Gateway API resources
- **Safe cleanup**: deletes completed jobs, failed/succeeded pods; reports
  (but does not delete) pending PVCs
- Expand/collapse all controls

### Configuration Tab
- **Curated editor**: CPU, memory, disk, root disk (grow-only), k8s enabled +
  version, advanced toggles (mountInotify, forwardAgent, Rosetta, binfmt)
- **k3s version picker**: fetches releases from the GitHub API, filters out
  release candidates, guarantees the currently-running version is always
  selectable
- **DNS list editor** and **Docker log-opts** fields (numeric quoting prevents
  daemon crashes)
- **Raw YAML tab**: free-form editing with comment preservation
- **Atomic saves** with a restart prompt when the VM is running

### Power Bar
- Color circle (green = running, gray = stopped) + contextual start/stop button
- Live streaming logs (collapsible) during start/stop operations

## Requirements

- macOS 13+
- Swift 5.9+ (Xcode Command Line Tools)
- [Colima](https://github.com/abiosoft/colima) (`/opt/homebrew/bin/colima`)
- [kubectl](https://kubernetes.io/docs/tasks/tools/) (`/opt/homebrew/bin/kubectl`)
- [Homebrew](https://brew.sh) (`/opt/homebrew/bin` or `/usr/local/bin`)

The app automatically injects Homebrew paths into all spawned process
environments. GUI apps launched from Finder/Dock inherit launchd's minimal
PATH (`/usr/bin:/bin:/usr/sbin:/sbin`) which omits Homebrew — without this
enrichment, `colima` fails with "lima not found" and `kubectl` is unreachable.

## Installation

### Quick install (recommended)

```bash
git clone https://github.com/linwalth/colima-command-center.git
cd colima-command-center
./scripts/build.sh
```

This assembles the `.app` bundle into `~/Applications/Colima Command Center.app`,
signs it ad hoc, and registers it with Spotlight. Launch it from there or via
Spotlight search ("colima command").

### Manual build

```bash
swift build -c release
```

The binary lands in `.build/release/ColimaCommandCenter`. For full functionality
(bundle, icon, localization, resource embedding), use `build.sh` instead.

## Configuration

### Colima Home

Resolved in priority order:

1. `COLIMA_HOME` environment variable
2. `~/.config/colima` (XDG)
3. `~/.colima` (legacy)

### Colima Profiles

Defaults to `default`. Override with the `COLIMA_PROFILE` environment variable.
All `colima` commands (start, stop, ssh, list) respect the profile.

### Kubernetes Context

The app uses the same context as `kubectl`. An `ensureContext()` call verifies
the Colima context is active before each query — useful when switching between
contexts with tools like [kubeswitch](https://github.com/danielfoehrKn/kubeswitch).

### App Definitions (`apps.json`)

The startup sequence scales configured apps to 1 replica; shutdown scales them
to 0. Define your workloads in `Resources/apps.json`:

```json
[
  { "ns": "myapp", "name": "frontend", "defaultReplicas": 1, "kind": "deployment" },
  { "ns": "myapp", "name": "database", "defaultReplicas": 1, "kind": "statefulset" }
]
```

Edit this file to match your own workloads. No code changes needed.

## Localization

German (default) and English. Follows the macOS system language.
Translation strings live in `Resources/de.lproj/` and `Resources/en.lproj/Localizable.strings`.

## Architecture

```
Sources/ColimaCommandCenter/
  main.swift              — App bootstrap (accessory policy)
  AppDelegate.swift       — Coordinates StatusBar, Lifecycle, and Window
  StatusBar.swift         — NSStatusItem + menu, explicit start/stop callbacks
  MainWindow.swift        — Main window (TabView + PowerBar), PowerViewModel
  Lifecycle.swift         — colima list checks, startStream/stopStream/restart
  ShellCapture.swift       — Process runner with 30s timeout watchdog (process-group kill)
  ClusterOps.swift         — Native VM/Docker/k3s operations, colimaSSH (bash -c wrapper)
  StatusCollector.swift    — Structured VM metrics + section assembly for Status tab
  KubeStatus.swift        — kubectl resource queries (two-probe gate, fault-tolerant)
  K3sVersions.swift       — GitHub API k3s release fetcher (RC filter, current-version guarantee)
  ColimaConfig.swift      — Line-based YAML parser/writer (preserves comments)
  EditorViewModel.swift   — Config load/save + restart flow
  EditorView.swift        — SwiftUI config editor (curated + raw)
  HealthView.swift        — Status tab: sub-tabs (VM/Docker/K8s), gauges, sparkline, cleanup
  HealthViewModel.swift   — Auto-refresh, load history tracking, cleanup triggers
  DependencyChecker.swift — colima/kubectl detection (Homebrew paths + which)
  Notify.swift            — UNUserNotificationCenter wrapper
  L10n.swift              — Localization helper (NSLocalizedString)

Resources/
  de.lproj/Localizable.strings — German strings
  en.lproj/Localizable.strings — English strings
  apps.json                    — App definitions for startup/shutdown scaling
  AppIcon.icns                 — App icon
```

## Technical Highlights

- **Process-group kill** (`kill(-pgid, SIGKILL)`) prevents pipe deadlocks when
  `colima ssh` grandchild processes keep stdout open after the parent exits
- **`colima list` instead of `colima status`** for status checks — always fast,
  no SSH socket hanging during VM shutdown
- **`bash -c` wrapper for `colima ssh`** — colima execs argv directly (no
  shell), so single-string commands would hit ENOENT
- **`enrichedEnvironment()`** — prepends Homebrew paths for GUI-launched
  processes (launchd PATH omits `/opt/homebrew/bin`)
- **Two-probe gate** in KubeStatus — the panel shows data as long as at least
  one probe (deployments OR nodes) succeeds, surviving transient API hiccups
- **Safe cleanup** — Docker: only exited/dangling; K8s: only succeeded/failed
  pods + completed jobs, pending PVCs reported but never deleted

## License

MIT
