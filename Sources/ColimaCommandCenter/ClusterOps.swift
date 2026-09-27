import Foundation

/// Native cluster operations — inspired by ctl/deployments.sh, but calls
/// colima/kubectl directly. No shell-script dependency.
enum ClusterOps {

    // MARK: - App definitions (mirrors deployments.sh DEFAULTS)

    struct AppDef: Codable, Sendable {
        let ns: String
        let name: String
        let defaultReplicas: Int
        let kind: String   // "deployment" or "statefulset"
    }

    static let apps: [AppDef] = loadApps()

    private static func loadApps() -> [AppDef] {
        // Load app definitions from bundled apps.json. Users can customize
        // this file to match their own k3s workloads without modifying code.
        guard let url = Bundle.main.url(forResource: "apps", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([AppDef].self, from: data) else {
            return []
        }
        return decoded
    }

    // MARK: - kubectl helpers

    private static func kubectl(_ args: [String]) -> (stdout: String, exitCode: Int32) {
        guard let path = KubeStatus.resolveKubectl() else { return ("", -1) }
        return ShellCapture.run(path, args: args)
    }

    private static func colimaSSH(_ cmd: String) -> (stdout: String, exitCode: Int32) {
        // colima ssh execs argv directly (first arg = binary, rest = args);
        // it does NOT invoke a shell. Passing the whole command as one string
        // makes colima look for a binary literally named "df -hP ..." → ENOENT.
        // Route through `bash -c` so the command string is parsed as a script,
        // supporting pipes, redirects, quotes, and nested `sudo bash -c '...'`.
        //
        // --profile is a GLOBAL flag: it must come BEFORE the subcommand
        // (`colima -p X ssh -- ...`), not after `ssh` — colima stops option
        // parsing at the subcommand boundary. Using `-p` shorthand.
        let profile = AppPaths.colimaProfile
        var args: [String] = []
        if profile != "default" { args += ["-p", profile] }
        args += ["ssh", "--", "bash", "-c", cmd]
        return ShellCapture.run(AppPaths.colima, args: args)
    }

    /// Build colima start/stop args with --profile for non-default profiles.
    /// --profile is global, so it precedes the action verb.
    private static func colimaStartStopArgs(_ action: String) -> [String] {
        let profile = AppPaths.colimaProfile
        if profile == "default" { return [action] }
        return ["-p", profile, action]
    }

    // MARK: - Context

    /// Detect the active colima context name (handles non-default profiles).
    /// Colima contexts are named "colima" (default) or "colima-<profile>".
    static func activeProfile() -> String? {
        let ctx = kubectl(["config", "current-context"])
        let name = ctx.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.hasPrefix("colima") { return name }
        return nil
    }

    static func ensureContext() {
        let ctx = kubectl(["config", "current-context"])
        let name = ctx.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.hasPrefix("colima") {
            // Find first colima context available.
            let ctxs = kubectl(["config", "get-contexts", "-o", "name"])
            for line in ctxs.stdout.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("colima") {
                    _ = kubectl(["config", "use-context", trimmed])
                    return
                }
            }
        }
    }

    // MARK: - Scaling

    static func scaleApps(to replicas: Int) {
        for app in apps {
            _ = kubectl(["scale", app.kind, app.name, "-n", app.ns, "--replicas=\(replicas)"])
        }
    }

    // MARK: - Startup

    static func startupStream(onOutput: @escaping (String) -> Void) -> Int32 {
        onOutput(L10n.tr("ops.starting_vm"))
        _ = Shell.stream(AppPaths.colima, args: colimaStartStopArgs("start"), onOutput: onOutput)

        // Poll colima list until OUR profile reports Running.
        onOutput(L10n.tr("ops.waiting_vm"))
        let profile = AppPaths.colimaProfile
        for _ in 0..<12 {
            Thread.sleep(forTimeInterval: 5)
            let lst = ShellCapture.run(AppPaths.colima, args: ["list"], timeout: 15)
            let isRunning = lst.stdout
                .components(separatedBy: "\n")
                .dropFirst()
                .contains { line in
                    let cols = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).filter { !$0.isEmpty }
                    guard cols.first == Substring(profile) else { return false }
                    return line.range(of: "\\bRunning\\b", options: .regularExpression) != nil
                }
            if isRunning { break }
        }

        // Ensure docker daemon is running (may be down after unclean stop).
        let dockerActive = colimaSSH("sudo systemctl is-active docker").stdout
        if !dockerActive.contains("active") {
            onOutput(L10n.tr("ops.starting_docker"))
            _ = colimaSSH("sudo systemctl reset-failed docker.socket docker.service")
            _ = colimaSSH("sudo systemctl start docker")
            Thread.sleep(forTimeInterval: 3)
        }

        // Ensure k3s is running (colima start doesn't restart k3s if VM existed).
        let k3sActive = colimaSSH("sudo systemctl is-active k3s").stdout
        if !k3sActive.contains("active") {
            onOutput(L10n.tr("ops.starting_k3s"))
            _ = colimaSSH("sudo systemctl enable k3s")
            _ = colimaSSH("sudo systemctl start k3s")
            for _ in 0..<12 {
                Thread.sleep(forTimeInterval: 5)
                let st = colimaSSH("sudo systemctl is-active k3s").stdout
                if st.contains("active") { break }
            }
        }

        onOutput(L10n.tr("ops.fixing_context"))
        ensureContext()

        onOutput(L10n.tr("ops.running_doctor"))
        _ = doctor().0

        onOutput(L10n.tr("ops.scaling_apps"))
        scaleApps(to: 1)

        onOutput(L10n.tr("ops.done"))
        return 0
    }

    // MARK: - Shutdown

    static func shutdownStream(onOutput: @escaping (String) -> Void) -> Int32 {
        onOutput(L10n.tr("ops.scaling_down"))
        scaleApps(to: 0)
        Thread.sleep(forTimeInterval: 3)

        onOutput(L10n.tr("ops.stopping_k3s"))
        _ = colimaSSH("sudo systemctl stop k3s")
        Thread.sleep(forTimeInterval: 2)

        onOutput(L10n.tr("ops.stopping_vm"))
        let rc = Shell.stream(AppPaths.colima, args: colimaStartStopArgs("stop"), onOutput: onOutput)
        onOutput(L10n.tr("ops.done"))
        return rc
    }

    // Public wrappers for StatusCollector (keep private impl unchanged).
    static func colimaSSHPublic(_ cmd: String) -> (stdout: String, exitCode: Int32) {
        colimaSSH(cmd)
    }
    static func formatDFPublic(_ raw: String) -> String {
        formatDF(raw)
    }

    private static func formatDF(_ raw: String) -> String {
        var lines: [String] = []
        for line in raw.components(separatedBy: "\n").dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let cols = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).filter { !$0.isEmpty }
            if cols.count >= 6 {
                let mount = String(cols[5])
                let used = String(cols[2])
                let total = String(cols[1])
                let pct = String(cols[4])
                lines.append("  \(mount.padding(toLength: 20, withPad: " ", startingAt: 0)) \(used) used / \(total) total (\(pct))")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Docker prune

    @discardableResult
    static func dockerPrune() -> Int32 {
        _ = colimaSSH("docker container prune -f")
        _ = colimaSSH("docker image prune -f")
        _ = colimaSSH("docker builder prune -f")
        return 0
    }

    // MARK: - Stale pods

    @discardableResult
    static func cleanupStalePods() -> String {
        var lines: [String] = []
        for phase in ["Succeeded", "Unknown", "Failed"] {
            let r = kubectl(["delete", "pods", "-A", "--field-selector=status.phase=\(phase)"])
            let out = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !out.isEmpty { lines.append(out) }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Doctor

    static func doctor() -> (String, Int32) {
        var output: [String] = []
        var hadError = false

        // Ensure kubectl context is set BEFORE any kubectl calls — if the
        // context is empty (e.g. kubeswitch cleared it), kubectl falls back to
        // localhost:8080 and every subsequent call wastes time on retries.
        ensureContext()

        // Determine node name dynamically (supports non-default profiles).
        // Retry up to 3x with 2s delay — kubectl can transiently fail during
        // k3s warm-up (API not ready yet) which would falsely mark the whole
        // doctor run as "failed".
        let nodes = kubectl(["get", "nodes", "-o", "jsonpath={.items[0].metadata.name}"])
        var nodeName = nodes.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if nodeName.isEmpty {
            for _ in 0..<3 {
                Thread.sleep(forTimeInterval: 2)
                let retry = kubectl(["get", "nodes", "-o", "jsonpath={.items[0].metadata.name}"])
                nodeName = retry.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                if !nodeName.isEmpty { break }
            }
        }
        if nodeName.isEmpty {
            hadError = true
            output.append(L10n.tr("ops.node_unreachable"))
            return (output.joined(separator: "\n"), 1)
        }

        // Check DiskPressure taint
        let desc = kubectl(["describe", "node", nodeName])
        let hasTaint = desc.stdout.contains("disk-pressure")
        if hasTaint {
            output.append(L10n.tr("ops.diskpressure_detected"))
            dockerPrune()
            output.append(L10n.tr("ops.restarting_k3s"))
            _ = colimaSSH("sudo systemctl restart k3s")
            Thread.sleep(forTimeInterval: 15)
            ensureContext()
            _ = kubectl(["taint", "nodes", nodeName, "node.kubernetes.io/disk-pressure:NoSchedule-"])
            output.append(L10n.tr("ops.diskpressure_cleared"))
        } else {
            output.append(L10n.tr("ops.no_diskpressure"))
        }

        // Cleanup stale pods
        let stale = cleanupStalePods()
        if !stale.isEmpty { output.append(stale) }

        // Cleanup stale kubelet pod directories
        let activeUIDs = kubectl(["get", "pods", "-A", "-o", "jsonpath={.items[*].metadata.uid}"])
        if !activeUIDs.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let uids = activeUIDs.stdout
            // Validate UIDs are alphanumeric (defense against injection).
            let validUIDs = uids.split(separator: " ").map(String.init).filter {
                $0.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil
            }
            if validUIDs.isEmpty { return (output.joined(separator: "\n"), hadError ? 1 : 0) }
            let uidList = validUIDs.joined(separator: "|")
            // Single quotes protect bash vars ($d, $uid, $(basename)) from the
            // outer bash invoked by colimaSSH. \(uidList) is Swift interpolation
            // (NOT $uidList — that's literal text in Swift strings) injecting
            // the validated UID list. UIDs are regex-validated [A-Za-z0-9_-]+
            // so embedding inside single quotes is injection-safe.
            let cmd = """
            sudo bash -c 'for d in /var/lib/kubelet/pods/*/; do uid=$(basename "$d"); if ! echo "\(uidList)" | grep -Fqw "$uid"; then echo "$d"; fi; done'
            """
            let staleDirs = colimaSSH(cmd)
            let dirs = staleDirs.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !dirs.isEmpty {
                let count = dirs.components(separatedBy: "\n").count
                output.append(L10n.tr("ops.stale_dirs_removing", count))
                for dir in dirs.components(separatedBy: "\n") {
                    let escaped = dir.replacingOccurrences(of: "'", with: "'\\''")
                    _ = colimaSSH("sudo rm -rf '\(escaped)'")
                }
            }
        }

        // Prune Docker if disk getting full
        let dfRaw = colimaSSH("df -hP /var/lib/docker")
        let pct = parseDiskPercent(dfRaw.stdout)
        if let pct = pct, pct >= 75 {
            output.append(L10n.tr("ops.disk_full_prune", pct))
            dockerPrune()
        }

        return (output.joined(separator: "\n"), hadError ? 1 : 0)
    }

    private static func parseDiskPercent(_ dfOutput: String) -> Int? {
        let lines = dfOutput.components(separatedBy: "\n")
        guard let lastLine = lines.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            return nil
        }
        let cols = lastLine.split(whereSeparator: { $0 == " " || $0 == "\t" }).filter { !$0.isEmpty }
        guard cols.count >= 5 else { return nil }
        let pctStr = String(cols[4]).replacingOccurrences(of: "%", with: "")
        return Int(pctStr)
    }

    // MARK: - Safe Cleanup Operations

    /// Gentle Docker cleanup — only removes DANGLING images and EXITED containers.
    /// Never touches running containers, tagged images, or volumes in use.
    static func safeDockerClean() -> String {
        var results: [String] = []

        // Exited containers only (--filter status=exited).
        let cont = colimaSSH("docker container prune -f --filter status=exited")
        results.append("Container: \(cont.stdout.trimmingCharacters(in: .whitespacesAndNewlines))")

        // Dangling images only (untagged, unreferenced).
        let img = colimaSSH("docker image prune -f --filter dangling=true")
        results.append("Images: \(img.stdout.trimmingCharacters(in: .whitespacesAndNewlines))")

        // Unused build cache.
        let bc = colimaSSH("docker builder prune -f --filter type=regular")
        results.append("Build Cache: \(bc.stdout.trimmingCharacters(in: .whitespacesAndNewlines))")

        return results.joined(separator: "\n")
    }

    /// Safe K8s cleanup — completed jobs, failed/succeeded pods, pending PVCs.
    /// Never touches running pods, bound PVCs, or active jobs.
    static func safeK8sClean() -> String {
        guard let kc = KubeStatus.resolveKubectl() else { return "kubectl not found" }
        var results: [String] = []

        // Delete completed jobs (succeeded).
        let jobs = ShellCapture.run(kc, args: ["delete", "jobs", "-A", "--field-selector=status.successful=1"])
        results.append("Completed Jobs: \(jobs.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "none" : jobs.stdout.trimmingCharacters(in: .whitespacesAndNewlines))")

        // Delete failed pods (phase=Failed).
        let failed = ShellCapture.run(kc, args: ["delete", "pods", "-A", "--field-selector=status.phase=Failed"])
        results.append("Failed Pods: \(failed.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "none" : failed.stdout.trimmingCharacters(in: .whitespacesAndNewlines))")

        // Delete succeeded pods (phase=Succeeded — completed jobs leave these).
        let succ = ShellCapture.run(kc, args: ["delete", "pods", "-A", "--field-selector=status.phase=Succeeded"])
        results.append("Succeeded Pods: \(succ.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "none" : succ.stdout.trimmingCharacters(in: .whitespacesAndNewlines))")

        // List pending PVCs (don't auto-delete — just report).
        let pvc = ShellCapture.run(kc, args: ["get", "pvc", "-A", "--field-selector=status.phase=Pending", "-o", "custom-columns=NS:.metadata.namespace,NAME:.metadata.name,AGE:.metadata.creationTimestamp", "--no-headers"])
        let pvcTrimmed = pvc.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        results.append("Pending PVCs: \(pvcTrimmed.isEmpty ? "none" : pvcTrimmed)")

        return results.joined(separator: "\n")
    }
}
