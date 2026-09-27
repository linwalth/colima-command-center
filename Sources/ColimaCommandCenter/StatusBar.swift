import Cocoa

final class StatusBarController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var cachedDeps: DependencyChecker.Status?
    private var lastDepCheck: Date?
    private var isCurrentlyRunning = false
    private var isRefreshing = false
    var onToggle: (() -> Void)?
    var onStart: (() -> Void)?
    var onStop: (() -> Void)?
    var onOpenMainWindow: (() -> Void)?
    var onOpenEditor: (() -> Void)?
    var onOpenHealth: (() -> Void)?
    var onInstallColima: (() -> Void)?

    init() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "shippingbox", accessibilityDescription: "Colima")
        }
        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()

        let statusEntry = NSMenuItem(title: L10n.tr("status.loading"), action: nil, keyEquivalent: "")
        statusEntry.tag = StatusTag.status.rawValue
        statusEntry.isEnabled = false
        menu.addItem(statusEntry)

        menu.addItem(.separator())

        let toggle = NSMenuItem(title: L10n.tr("menu.toggle"), action: #selector(toggleAction), keyEquivalent: "t")
        toggle.target = self
        menu.addItem(toggle)

        let editor = NSMenuItem(title: L10n.tr("menu.editor"), action: #selector(editorAction), keyEquivalent: ",")
        editor.target = self
        menu.addItem(editor)

        let health = NSMenuItem(title: L10n.tr("menu.health"), action: #selector(healthAction), keyEquivalent: "h")
        health.target = self
        health.tag = StatusTag.clusterDependent.rawValue
        health.isHidden = true
        menu.addItem(health)

        let clusterSep = NSMenuItem.separator()
        clusterSep.tag = StatusTag.clusterSeparator.rawValue
        clusterSep.isHidden = true
        menu.addItem(clusterSep)

        let quit = NSMenuItem(title: L10n.tr("menu.quit"), action: #selector(quitAction), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    func refreshStatus() {
        // Prevent overlapping refresh cycles: the 5s timer can fire while a
        // previous checkStatus (10s timeout) is still in flight. Without this
        // guard, two updateMenu calls race and the menu flickers.
        guard !isRefreshing else { return }
        isRefreshing = true
        let now = Date()
        let deps: DependencyChecker.Status
        if let cached = cachedDeps, let last = lastDepCheck, now.timeIntervalSince(last) < 300 {
            deps = cached
        } else {
            deps = DependencyChecker.check()
            cachedDeps = deps
            lastDepCheck = now
        }
        if !deps.allPresent {
            DispatchQueue.main.async {
                self.isRefreshing = false
                self.updateMenuMissingDependencies(deps)
            }
            return
        }
        if !AppPaths.colimaInitialized {
            DispatchQueue.main.async {
                self.isRefreshing = false
                self.updateMenuNotInitialized()
            }
            return
        }
        Lifecycle.shared.checkStatus { running in
            DispatchQueue.main.async {
                self.isRefreshing = false
                self.updateMenu(running: running)
            }
        }
    }

    private func updateMenuMissingDependencies(_ deps: DependencyChecker.Status) {
        guard let menu = statusItem.menu,
              let item = menu.item(withTag: StatusTag.status.rawValue) else { return }
        let missing = deps.missingNames.joined(separator: ", ")
        item.title = L10n.tr("status.missing_deps", missing)
        if let toggle = menu.items.first(where: { $0.action == #selector(StatusBarController.toggleAction) }) {
            toggle.title = L10n.tr("menu.install_missing")
            toggle.action = #selector(installAction)
            toggle.target = self
        }
        for mi in menu.items where mi.tag == StatusTag.clusterDependent.rawValue
                          || mi.tag == StatusTag.clusterSeparator.rawValue {
            mi.isHidden = true
        }
    }

    private func updateMenuNotInitialized() {
        guard let menu = statusItem.menu,
              let item = menu.item(withTag: StatusTag.status.rawValue) else { return }
        item.title = L10n.tr("status.not_initialized")
        if let toggle = menu.items.first(where: { $0.action == #selector(StatusBarController.installAction) }) {
            toggle.title = L10n.tr("menu.initialize")
            toggle.action = #selector(toggleAction)
            toggle.target = self
        }
        for mi in menu.items where mi.tag == StatusTag.clusterDependent.rawValue
                          || mi.tag == StatusTag.clusterSeparator.rawValue {
            mi.isHidden = true
        }
    }

    /// Delayed re-check after a toggle, giving the VM time to settle.
    func refreshStatusDelayed(seconds: TimeInterval = 3) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.refreshStatus()
        }
    }

    private func updateMenu(running: Bool) {
        isCurrentlyRunning = running
        guard let menu = self.statusItem.menu,
              let item = menu.item(withTag: StatusTag.status.rawValue) else { return }
        item.title = running ? L10n.tr("status.running") : L10n.tr("status.stopped")
        if let toggle = menu.items.first(where: { $0.action == #selector(StatusBarController.toggleAction) || $0.action == #selector(StatusBarController.installAction) }) {
            toggle.title = running ? L10n.tr("menu.stop") : L10n.tr("menu.start")
            toggle.action = #selector(toggleAction)
            toggle.target = self
        }
        for mi in menu.items where mi.tag == StatusTag.clusterDependent.rawValue
                          || mi.tag == StatusTag.clusterSeparator.rawValue {
            mi.isHidden = !running
        }
    }

    @objc private func toggleAction() {
        // Dispatch based on the label the user saw, not a re-guessed status.
        // If label said "Stopp" (isCurrentlyRunning), always stop.
        // If label said "Start" (!isCurrentlyRunning), always start.
        // Lifecycle.start/stop do a fresh checkStatus and noop if already in
        // the target state — so a stale label causes a safe noop, not a wrong action.
        if isCurrentlyRunning { onStop?() } else { onStart?() }
    }
    @objc private func editorAction() { onOpenEditor?() }
    @objc private func healthAction() { onOpenHealth?() }
    @objc private func installAction() { onInstallColima?() }
    @objc private func quitAction() { NSApp.terminate(nil) }
}

private enum StatusTag: Int {
    case status = 100
    case clusterDependent = 200
    case clusterSeparator = 201
}
