import Foundation

/// Fetches raw kubectl resource output for display, organized into
/// collapsible sections. Deployments are top-level; Pods grouped per
/// namespace. Optional CRDs tolerated.
struct KubeStatus {
    struct Section: Identifiable {
        var id: String { title }
        let title: String
        let raw: String
        var collapsedByDefault: Bool = false
    }

    static func run() -> [Section]? {
        guard let kubectl = resolveKubectl() else { return nil }

        // Ensure kubectl context is set — kubeswitch can clear it, leaving
        // kubectl to fall back to localhost:8080 and fail every query.
        ClusterOps.ensureContext()

        // Probe cluster reachability with two independent queries so a single
        // transient failure (k3s warm-up, brief API hiccup) doesn't blank the
        // whole panel. Only if BOTH fail do we treat the cluster as unreachable.
        let dep = ShellCapture.run(kubectl, args: ["get", "deploy", "-A"])
        let nodesProbe = ShellCapture.run(kubectl, args: ["get", "nodes"])
        let depBody = dep.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let nodesBody = nodesProbe.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let depOk = dep.exitCode == 0 && !depBody.isEmpty
        let nodesOk = nodesProbe.exitCode == 0 && !nodesBody.isEmpty
        if !depOk && !nodesOk { return nil }

        var sections: [Section] = []
        sections.append(makeSection(L10n.tr("kube.section.deployments"), ok: depOk, stdout: dep.stdout, collapsed: true))

        let pods = ShellCapture.run(kubectl, args: ["get", "pods", "-A"])
        sections.append(makeSection(L10n.tr("kube.section.pods"),
                                    ok: pods.exitCode == 0 && !pods.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                    stdout: pods.stdout, collapsed: true))

        sections.append(makeSection(L10n.tr("kube.section.nodes"), ok: nodesOk, stdout: nodesProbe.stdout, collapsed: true))

        let svc = ShellCapture.run(kubectl, args: ["get", "svc", "-A"])
        sections.append(makeSection(L10n.tr("kube.section.services"),
                                    ok: svc.exitCode == 0 && !svc.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                    stdout: svc.stdout, collapsed: true))

        let pvc = ShellCapture.run(kubectl, args: ["get", "pvc", "-A"])
        sections.append(makeSection(L10n.tr("kube.section.pvcs"),
                                    ok: pvc.exitCode == 0 && !pvc.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                    stdout: pvc.stdout, collapsed: true))

        for (title, args) in optionalQueries {
            let r = ShellCapture.run(kubectl, args: args)
            let body = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if body.isEmpty || r.exitCode != 0 {
                sections.append(Section(title: title, raw: L10n.tr("kube.not_installed"), collapsedByDefault: true))
            } else {
                sections.append(Section(title: title, raw: body, collapsedByDefault: true))
            }
        }

        return sections
    }

    private static func makeSection(_ title: String, ok: Bool, stdout: String, collapsed: Bool) -> Section {
        let body: String
        if ok {
            let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            body = trimmed.isEmpty ? L10n.tr("kube.empty_marker") : trimmed
        } else {
            body = L10n.tr("kube.query_failed")
        }
        return Section(title: title, raw: body, collapsedByDefault: collapsed)
    }

    static func resolveKubectl() -> String? {
        for candidate in ["/opt/homebrew/bin/kubectl", "/usr/local/bin/kubectl"] {
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        let which = ShellCapture.run("/usr/bin/which", args: ["kubectl"])
        let resolved = which.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return resolved.isEmpty ? nil : resolved
    }

    private static let optionalQueries: [(String, [String])] = [
        (L10n.tr("kube.section.flux"), ["get", "gitrepositories,kustomizations,helmreleases", "-A"]),
        (L10n.tr("kube.section.gateway"), ["get", "gateways,httproutes,tcproutes", "-A"]),
    ]
}
