import Cocoa
import SwiftUI

@MainActor
final class EditorViewModel: ObservableObject {
    @Published var cpu: Int = 4
    @Published var memory: Int = 8
    @Published var disk: Int = 50
    @Published var rootDisk: Int = 40

    // Floor values: disk/rootDisk are grow-only in colima (cannot shrink).
    // Loaded once from yaml; sliders clamp to [floor .. upper].
    @Published var diskFloor: Int = 50
    @Published var rootDiskFloor: Int = 40
    @Published var k8sEnabled: Bool = true
    @Published var k8sVersion: String = ""
    @Published var availableK3sVersions: [String] = []
    @Published var loadingVersions = false
    @Published var mountInotify: Bool = true
    @Published var forwardAgent: Bool = false
    @Published var rosetta: Bool = false
    @Published var binfmt: Bool = true
    @Published var rawYAML: String = "" { didSet { if !suppressRawDirty { rawDirty = true } } }

    @Published var dnsEntries: [DNSEntry] = []
    @Published var dockerLogMaxSize: String = "10m"
    @Published var dockerLogFileCount: String = "3"

    @Published var errorMessage: String?
    @Published var saved = false
    @Published var isLoading = true
    @Published var showRestartPrompt = false

    private var rawDirty = false
    private var suppressRawDirty = false
    private var configRaw: String?
    private var hasLoaded = false

    init() {}

    func fetchK3sVersions() {
        loadingVersions = true
        K3sVersions.fetch(currentVersion: k8sVersion.isEmpty ? nil : k8sVersion) { [weak self] versions in
            DispatchQueue.main.async {
                self?.availableK3sVersions = versions
                self?.loadingVersions = false
            }
        }
    }

    // MARK: - Reload (background parse, main apply — no self captured in bg)

    func reload() {
        guard !hasLoaded || !isLoading else { return }
        hasLoaded = true
        isLoading = true
        let path = AppPaths.colimaConfig
        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<Snapshot, Error>
            do {
                let cfg = try ColimaConfig(path: path)
                let snap = Snapshot(
                    cpu: cfg.intValue("cpu") ?? 4,
                    memory: cfg.intValue("memory") ?? 8,
                    disk: cfg.intValue("disk") ?? 50,
                    rootDisk: cfg.intValue("rootDisk") ?? 40,
                    k8sEnabled: cfg.nestedBool("kubernetes.enabled"),
                    k8sVersion: cfg.nestedScalar("kubernetes.version") ?? "",
                    mountInotify: cfg.boolValue("mountInotify"),
                    forwardAgent: cfg.boolValue("forwardAgent"),
                    rosetta: cfg.boolValue("rosetta"),
                    binfmt: cfg.boolValue("binfmt"),
                    dns: cfg.nestedList("network.dns").map(DNSEntry.init),
                    dockerLogMaxSize: cfg.nestedScalar("docker.log-opts.max-size") ?? "10m",
                    dockerLogFileCount: cfg.nestedScalar("docker.log-opts.max-file") ?? "3",
                    raw: cfg.raw
                )
                result = .success(snap)
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch result {
                case .success(let snap):
                    self.apply(snap)
                    self.configRaw = snap.raw
                    self.isLoading = false
                    self.fetchK3sVersions()
                case .failure(let err):
                    let nsErr = err as NSError
                    if nsErr.domain == NSCocoaErrorDomain && nsErr.code == 260 {
                        // File not found — colima not initialized yet.
                        self.errorMessage = L10n.tr("editor.no_config")
                    } else {
                        self.errorMessage = L10n.tr("msg.read_failed_prefix", err.localizedDescription)
                    }
                    self.isLoading = false
                }
            }
        }
    }

    struct Snapshot: Sendable {
        let cpu, memory, disk, rootDisk: Int
        let k8sEnabled: Bool
        let k8sVersion: String
        let mountInotify, forwardAgent, rosetta, binfmt: Bool
        let dns: [DNSEntry]
        let dockerLogMaxSize, dockerLogFileCount: String
        let raw: String
    }

    private func apply(_ s: Snapshot) {
        suppressRawDirty = true
        cpu = s.cpu; memory = s.memory; disk = s.disk; rootDisk = s.rootDisk
        diskFloor = s.disk; rootDiskFloor = s.rootDisk
        k8sEnabled = s.k8sEnabled; k8sVersion = s.k8sVersion
        mountInotify = s.mountInotify; forwardAgent = s.forwardAgent
        rosetta = s.rosetta; binfmt = s.binfmt
        dnsEntries = s.dns
        dockerLogMaxSize = s.dockerLogMaxSize
        dockerLogFileCount = s.dockerLogFileCount
        rawYAML = s.raw
        suppressRawDirty = false
        rawDirty = false
    }

    // MARK: - Save (capture on main, mutate+write off main, apply result on main)

    func save() {
        let inputs = SaveInputs(
            cpu: cpu, memory: memory, disk: disk, rootDisk: rootDisk,
            k8sEnabled: k8sEnabled, k8sVersion: k8sVersion,
            mountInotify: mountInotify, forwardAgent: forwardAgent,
            rosetta: rosetta, binfmt: binfmt,
            dns: dnsEntries.map(\.value).filter { !$0.isEmpty },
            dockerLogMaxSize: dockerLogMaxSize, dockerLogFileCount: dockerLogFileCount,
            rawOverride: rawDirty ? rawYAML : nil
        )
        guard let baseRaw = configRaw else {
            errorMessage = L10n.tr("msg.save_failed_prefix", "config not loaded")
            return
        }
        let path = AppPaths.colimaConfig
        DispatchQueue.global(qos: .userInitiated).async {
            var cfg = ColimaConfig(path: path, raw: baseRaw)
            cfg.setInt("cpu", inputs.cpu)
            cfg.setInt("memory", inputs.memory)
            cfg.setInt("disk", inputs.disk)
            cfg.setInt("rootDisk", inputs.rootDisk)
            cfg.setBool("mountInotify", inputs.mountInotify)
            cfg.setBool("forwardAgent", inputs.forwardAgent)
            cfg.setBool("rosetta", inputs.rosetta)
            cfg.setBool("binfmt", inputs.binfmt)
            cfg.setNestedBool("kubernetes.enabled", inputs.k8sEnabled)
            cfg.setNestedScalar("kubernetes.version", inputs.k8sVersion)
            cfg.setNestedList("network.dns", inputs.dns)
            cfg.setNestedScalar("docker.log-opts.max-size", inputs.dockerLogMaxSize)
            cfg.setNestedScalar("docker.log-opts.max-file", inputs.dockerLogFileCount)
            // If raw tab was edited, apply it FIRST, then re-apply curated
            // setters on top so neither side silently loses the other.
            if let raw = inputs.rawOverride { cfg.raw = raw }
            cfg.setInt("cpu", inputs.cpu)
            cfg.setInt("memory", inputs.memory)
            cfg.setInt("disk", inputs.disk)
            cfg.setInt("rootDisk", inputs.rootDisk)
            cfg.setBool("mountInotify", inputs.mountInotify)
            cfg.setBool("forwardAgent", inputs.forwardAgent)
            cfg.setBool("rosetta", inputs.rosetta)
            cfg.setBool("binfmt", inputs.binfmt)
            cfg.setNestedBool("kubernetes.enabled", inputs.k8sEnabled)
            cfg.setNestedScalar("kubernetes.version", inputs.k8sVersion)
            cfg.setNestedList("network.dns", inputs.dns)
            cfg.setNestedScalar("docker.log-opts.max-size", inputs.dockerLogMaxSize)
            cfg.setNestedScalar("docker.log-opts.max-file", inputs.dockerLogFileCount)

            let outcome: Result<String, Error>
            do {
                try cfg.save()
                outcome = .success(cfg.raw)
            } catch {
                outcome = .failure(error)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch outcome {
                case .success(let newRaw):
                    self.saved = true
                    self.errorMessage = nil
                    self.configRaw = newRaw
                    self.suppressRawDirty = true
                    self.rawYAML = newRaw
                    self.suppressRawDirty = false
                    self.rawDirty = false
                    self.checkRunningForRestartPrompt()
                case .failure(let err):
                    self.errorMessage = L10n.tr("msg.save_failed_prefix", err.localizedDescription)
                }
            }
        }
    }

    struct SaveInputs: Sendable {
        let cpu, memory, disk, rootDisk: Int
        let k8sEnabled: Bool
        let k8sVersion: String
        let mountInotify, forwardAgent, rosetta, binfmt: Bool
        let dns: [String]
        let dockerLogMaxSize, dockerLogFileCount: String
        let rawOverride: String?
    }

    private func checkRunningForRestartPrompt() {
        Lifecycle.shared.checkStatus { [weak self] running in
            DispatchQueue.main.async { [weak self] in
                if running { self?.showRestartPrompt = true }
            }
        }
    }

    func confirmRestart() {
        showRestartPrompt = false
        Lifecycle.shared.restart { exitCode in
            DispatchQueue.main.async {
                Notifier.shared.post(
                    title: L10n.tr("notif.restart_title"),
                    body: exitCode == 0 ? L10n.tr("notif.restarted") : L10n.tr("notif.restart_failed")
                )
            }
        }
    }

    func dismissRestart() {
        showRestartPrompt = false
    }
}

struct DNSEntry: Identifiable, Sendable {
    let id = UUID()
    var value: String
}
