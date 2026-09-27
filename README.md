# Colima Command Center

macOS-Menuleisten-App zur Steuerung der lokalen Colima-VM, Docker und k3s-Workloads.
Alle Operationen nativ in Swift implementiert — keine externen Shell-Skripte.

## Features

### Menuleiste
- **Status-Icon** (Shippingbox): Live-Status (Lauft/Gestoppt), 5s-Polling
- **Explizite Start/Stop-Buttons**: Aktion richtet sich nach Label, nicht nach geratenem Status
- **Multi-Profil-Support**: `COLIMA_PROFILE` env fur nicht-default Profile

### Status-Tab (Live-Dashboard)
Drei Sub-Tabs mit Auto-Refresh (5s):

#### Colima VM
- Animierter Status-Indicator (pulsierender Ring)
- **Kreisformige Gauges**: CPU %, RAM %, Data Disk % (Farb-Coding grun/gelb/rot)
- **Lineare Progress Bars**: Data Disk, Root Disk
- **Load Average Graph**: 3-Linien-Sparkline (1m blau / 5m lila / 15m orange) mit Referenzlinie bei voller CPU-Auslastung
- Runtime, Adresse, Arch, CPU-Cores

#### Docker
- Daemon-Status (active/inactive + running container count)
- Docker Storage (`docker system df` Tabelle)
- **Sanftes Cleanup**: Loscht nur beendete Container, nicht-getaggte Images, ungenutzten Build-Cache

#### Kubernetes
- Deployments, Pods, Nodes, Services, PVCs, Flux, Gateway API (kollapsible Sections)
- **Safe Cleanup**: Loscht erfolgreich abgeschlossene Jobs, fehlgeschlagene/abgeschlossene Pods; meldet Pending PVCs

### Konfigurations-Tab
- **Kuratierter Editor**: CPU, Memory, Disk, Root-Disk (grow-only), k8s Enabled + Version
- **k3s-Versions-Picker**: Lad Releases von GitHub API, filtert RCs, garantiert laufende Version in Dropdown
- **Advanced Toggles**: mountInotify, forwardAgent, Rosetta, binfmt
- **DNS-Listen-Editor** + **Docker log-opts** (numeric quoting verhindert Daemon-Crashes)
- **Raw YAML-Tab**: Freie Bearbeitung mit Kommentar-Erhaltung
- **Atomares Speichern** + Restart-Prompt bei laufender VM

### Power Bar
- Farbkreis (grun=luft, grau=gestoppt) + bedingter Start/Stopp-Button
- Live-Streaming-Logs (aufklappbar) wahrend Start/Stop

## Build & Install

```bash
./scripts/build.sh
```

Assembliert `.app` nach `~/Applications/Colima Command Center.app`, ad-hoc signiert, registriert bei Spotlight.

### Manueller Build (ohne Installer)

```bash
swift build -c release
```

Binary landet in `.build/release/ColimaCommandCenter`. Fur volle Funktionalitat (Bundle, Icon, Lokalisierung) `build.sh` verwenden.

## Anforderungen

- macOS 13+
- Swift 5.9+ (Command Line Tools)
- Colima (`/opt/homebrew/bin/colima`)
- kubectl (`/opt/homebrew/bin/kubectl`)
- Homebrew (`/opt/homebrew/bin` oder `/usr/local/bin`)

Die App injiziert Homebrew-Pfade automatisch in alle Process-Environments. GUI-Apps bekommen von launchd nur ein minimales PATH (`/usr/bin:/bin:/usr/sbin:/sbin`), das Homebrew-Verzeichnisse ausschliesst. Ohne diese Anreicherung wurden colima ("lima not found") und kubectl fehlschlagen. Ref: https://rares.blog/articles/macos-gui-path-codex

## Konfiguration

### Colima Home
Priorisierte Auflosung:
1. `COLIMA_HOME` env-Variable
2. `~/.config/colima` (XDG)
3. `~/.colima` (Legacy)

### Colima Profile
Default: `default`. Override via `COLIMA_PROFILE` env-Variable.

### Kubeconfig
App nutzt denselben Context wie `kubectl`. `ensureContext()` stellt sicher dass der Colima-Context aktiv ist (hilfreich bei kubeswitch-Nutzung).

## Lokalisierung

Deutsch (Standard) und Englisch. Folgt macOS-Systemsprache.
Strings in `Resources/de.lproj/` und `Resources/en.lproj/Localizable.strings`.

## Architektur

```
Sources/ColimaCommandCenter/
  main.swift              — App-Bootstrap (accessory policy)
  AppDelegate.swift       — Koordination StatusBar <-> Lifecycle <-> Window
  StatusBar.swift          — NSStatusItem + Menu, explizite Start/Stop-Callbacks
  MainWindow.swift         — Hauptfenster (TabView + PowerBar), PowerViewModel
  Lifecycle.swift          — colima list/status, startStream/stopStream/restart
  ShellCapture.swift       — Process-Runner mit 30s-Timeout-Watchdog (Process-Group-Kill)
  ClusterOps.swift         — Native VM/Docker/k3s-Operationen, colimaSSH (bash -c wrapper)
  StatusCollector.swift     — Strukturierte VM-Metriken + Section-Assembly fur Status-Tab
  KubeStatus.swift         — kubectl-Resource-Queries (two-probe gate, tolerant)
  K3sVersions.swift        — GitHub-API k3s-Release-Fetcher (RC-filter, current-version-guarantee)
  ColimaConfig.swift       — Zeilenbasierter YAML-Parser/Writer (Kommentar-Erhaltung)
  EditorViewModel.swift     — Config laden/speichern + Restart-Flow
  EditorView.swift          — SwiftUI Config-Editor (kuratiert + raw)
  HealthView.swift          — Status-Tab: Sub-Tabs (VM/Docker/K8s), Gauges, Sparkline, Cleanup
  HealthViewModel.swift     — Auto-Refresh, Load-History-Tracking, Cleanup-Trigger
  DependencyChecker.swift   — colima/kubectl Erkennung (Homebrew-Pfade + which)
  Notify.swift              — UNUserNotificationCenter Wrapper
  L10n.swift               — Localization-Helper (NSLocalizedString)

Resources/
  de.lproj/Localizable.strings — Deutsche Strings
  en.lproj/Localizable.strings — Englische Strings
  AppIcon.icns                  — App-Icon
```

## Technische Highlights

- **Process-Group kill** (`kill(-pgid, SIGKILL)`) verhindert Pipe-Deadlocks bei colima ssh Grandchild-Prozessen
- **`colima list` statt `colima status`** fur Status-Checks — immer schnell, kein SSH-Socket-Hanging
- **`bash -c` wrapper** fur `colima ssh` — colima execs argv direkt (keine Shell), Single-String-Commands wurden ENOENT
- **enrichedEnvironment()** — prepentet Homebrew-Pfade fur GUI-launched Processes (launchd PATH = `/usr/bin:/bin`)
- **Two-probe gate** in KubeStatus — Panel zeigt Daten solange mindestens eine Query (deploy ODER nodes) erfolgreich
- **Safe cleanup** — Docker: nur exited/dangling; K8s: nur succeeded/failed Pods + Jobs, Pending PVCs nur gemeldet
