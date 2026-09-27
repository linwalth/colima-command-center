import Cocoa
import SwiftUI

@MainActor
final class HealthViewModel: ObservableObject {
    @Published var vmMetrics = VMMetrics()
    @Published var vmSections: [KubeStatus.Section] = []
    @Published var dockerSections: [KubeStatus.Section] = []
    @Published var kubeSections: [KubeStatus.Section] = []
    @Published var collapsed: Set<String> = []
    @Published var isLoading = false
    @Published var lastUpdated: Date?
    @Published var subTab: Int = 0
    @Published var loadHistory1: [Double] = []
    @Published var loadHistory5: [Double] = []
    @Published var loadHistory15: [Double] = []
    @Published var isCleaningDocker = false
    @Published var dockerCleanResult: String?
    @Published var isCleaningK8s = false
    @Published var k8sCleanResult: String?

    private var refreshTimer: Timer?
    private var userToggled: Set<String> = []

    func refresh() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = StatusCollector.run()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.vmMetrics = result.metrics
                self.vmSections = result.vmSections
                self.dockerSections = result.dockerSections
                self.kubeSections = result.kubeSections
                // Track load history for sparkline (keep last 30 samples = 2.5min).
                if let l1 = result.metrics.loadAvg1 {
                    self.loadHistory1.append(l1)
                    if self.loadHistory1.count > 30 { self.loadHistory1.removeFirst() }
                }
                if let l5 = result.metrics.loadAvg5 {
                    self.loadHistory5.append(l5)
                    if self.loadHistory5.count > 30 { self.loadHistory5.removeFirst() }
                }
                if let l15 = result.metrics.loadAvg15 {
                    self.loadHistory15.append(l15)
                    if self.loadHistory15.count > 30 { self.loadHistory15.removeFirst() }
                }
                // Apply collapse defaults ONLY for titles the user has never
                // toggled. Once a user expands/collapses a section, remember
                // their choice and never override it on refresh.
                let allSections = result.vmSections + result.dockerSections + result.kubeSections
                for s in allSections where s.collapsedByDefault && !self.userToggled.contains(s.title) {
                    self.collapsed.insert(s.title)
                }
                let newTitles = Set(allSections.map { $0.title })
                self.collapsed = self.collapsed.intersection(newTitles)
                self.isLoading = false
                self.lastUpdated = Date()
            }
        }
    }

    func cleanDocker() {
        guard !isCleaningDocker else { return }
        isCleaningDocker = true
        dockerCleanResult = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = ClusterOps.safeDockerClean()
            DispatchQueue.main.async { [weak self] in
                self?.dockerCleanResult = result
                self?.isCleaningDocker = false
                self?.refresh()
            }
        }
    }

    func cleanK8s() {
        guard !isCleaningK8s else { return }
        isCleaningK8s = true
        k8sCleanResult = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = ClusterOps.safeK8sClean()
            DispatchQueue.main.async { [weak self] in
                self?.k8sCleanResult = result
                self?.isCleaningK8s = false
                self?.refresh()
            }
        }
    }

    func startAutoRefresh() {
        guard refreshTimer == nil else { return }
        // Synchronous quick status check FIRST so the dashboard shows the
        // correct running/stopped state immediately — no flash of "Stopped"
        // before the first async refresh completes. colima list is <1s.
        let running = Lifecycle.shared.quickCheckRunning()
        vmMetrics.isRunning = running
        vmMetrics.status = running ? "Running" : "Stopped"
        // Kick off full async refresh for detailed metrics.
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        RunLoop.main.add(refreshTimer!, forMode: .common)
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func toggleCollapsed(_ title: String) {
        userToggled.insert(title)
        if collapsed.contains(title) { collapsed.remove(title) }
        else { collapsed.insert(title) }
    }
}
