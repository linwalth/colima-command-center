import Cocoa
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController!
    private var mainWindow: MainWindowController?
    private var statusTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Notifier.shared.requestAuthorizationIfNeeded()
        NSApp.activate(ignoringOtherApps: false)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.statusBar = StatusBarController()
            self.statusBar.onToggle = { [weak self] in self?.handleToggle() }
            self.statusBar.onStart = { [weak self] in self?.handleStart() }
            self.statusBar.onStop = { [weak self] in self?.handleStop() }
            self.statusBar.onOpenMainWindow = { [weak self] in self?.openMainWindow(tab: nil) }
            self.statusBar.onOpenEditor = { [weak self] in self?.openMainWindow(tab: .editor) }
            self.statusBar.onOpenHealth = { [weak self] in self?.openMainWindow(tab: .health) }
            self.statusBar.onInstallColima = { [weak self] in self?.installColima() }
            self.statusBar.refreshStatus()
            let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
                self?.statusBar.refreshStatus()
            }
            RunLoop.main.add(timer, forMode: .common)
            self.statusTimer = timer
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusTimer?.invalidate()
    }

    private func handleToggle() {
        Lifecycle.shared.toggle { [weak self] wasRunning, exitCode in
            DispatchQueue.main.async { [weak self] in
                self?.statusBar.refreshStatus()
                self?.statusBar.refreshStatusDelayed()
                if exitCode == 0 {
                    Notifier.shared.post(
                        title: L10n.tr("notif.toggle_title"),
                        body: wasRunning ? L10n.tr("notif.stopped") : L10n.tr("notif.started")
                    )
                } else {
                    Notifier.shared.post(
                        title: L10n.tr("notif.toggle_title"),
                        body: wasRunning ? L10n.tr("notif.stop_failed") : L10n.tr("notif.start_failed")
                    )
                }
            }
        }
    }

    private func handleStart() {
        Lifecycle.shared.start { [weak self] wasAlreadyRunning, exitCode in
            DispatchQueue.main.async { [weak self] in
                self?.statusBar.refreshStatus()
                self?.statusBar.refreshStatusDelayed()
                if !wasAlreadyRunning && exitCode == 0 {
                    Notifier.shared.post(
                        title: L10n.tr("notif.toggle_title"),
                        body: L10n.tr("notif.started")
                    )
                }
            }
        }
    }

    private func handleStop() {
        Lifecycle.shared.stop { [weak self] wasAlreadyStopped, exitCode in
            DispatchQueue.main.async { [weak self] in
                self?.statusBar.refreshStatus()
                self?.statusBar.refreshStatusDelayed()
                if !wasAlreadyStopped && exitCode == 0 {
                    Notifier.shared.post(
                        title: L10n.tr("notif.toggle_title"),
                        body: L10n.tr("notif.stopped")
                    )
                }
            }
        }
    }

    private func openMainWindow(tab: MainTab?) {
        if mainWindow == nil {
            mainWindow = MainWindowController()
        }
        if let tab = tab {
            mainWindow?.selectTab(tab)
        }
        mainWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: false)
    }

    private func installColima() {
        let deps = DependencyChecker.check()
        let missing = deps.missingNames.joined(separator: ", ")
        let commands = deps.missingInstallCommands.joined(separator: "\n")

        let alert = NSAlert()
        alert.messageText = L10n.tr("install.title_deps", missing)
        alert.informativeText = L10n.tr("install.instructions_deps", commands)
        alert.addButton(withTitle: L10n.tr("install.run_brew"))
        alert.addButton(withTitle: L10n.tr("alert.cancel"))
        alert.alertStyle = .informational
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Show indeterminate progress while installing.
            let progress = NSAlert()
            progress.messageText = L10n.tr("install.installing")
            progress.informativeText = L10n.tr("install.installing_hint")
            progress.addButton(withTitle: "")
            progress.buttons.first?.isEnabled = false
            progress.alertStyle = .informational
            DispatchQueue.global(qos: .userInitiated).async {
                let brew = resolveBrew()
                if !deps.colima, !brew.isEmpty {
                    _ = Shell.sync(brew, args: ["install", "colima"])
                }
                if !deps.kubectl, !brew.isEmpty {
                    _ = Shell.sync(brew, args: ["install", "kubectl"])
                }
                if DependencyChecker.check().colima {
                    _ = Shell.sync(AppPaths.colima, args: ["start"])
                }
                DispatchQueue.main.async { [weak self] in
                    progress.window.orderOut(nil)
                    self?.statusBar.refreshStatus()
                    Notifier.shared.post(
                        title: L10n.tr("install.title_deps", ""),
                        body: L10n.tr("install.complete")
                    )
                }
            }
            progress.runModal()
        }
    }
}

/// Resolve brew path: ARM /opt/homebrew, Intel /usr/local, fallback which.
private func resolveBrew() -> String {
    for candidate in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"] {
        if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
    }
    let which = ShellCapture.run("/usr/bin/which", args: ["brew"])
    let resolved = which.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    return resolved
}
