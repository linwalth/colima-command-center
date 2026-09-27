import Foundation

/// Audits runtime dependencies (colima, kubectl, docker) and provides
/// brew install commands for missing ones.
enum DependencyChecker {

    struct Status {
        let colima: Bool
        let kubectl: Bool
        let docker: Bool
        let dockerDesktop: Bool

        /// Only colima + kubectl are required on the host. Docker runs
        /// inside the VM via `colima ssh -- docker`, not on the Mac.
        var allPresent: Bool { colima && kubectl }

        var missingInstallCommands: [String] {
            var cmds: [String] = []
            if !colima { cmds.append("brew install colima") }
            if !kubectl { cmds.append("brew install kubectl") }
            return cmds
        }

        var missingNames: [String] {
            var names: [String] = []
            if !colima { names.append("colima") }
            if !kubectl { names.append("kubectl") }
            return names
        }
    }

    static func check() -> Status {
        let colimaOk = binaryExists("colima", candidates: ["/opt/homebrew/bin/colima", "/usr/local/bin/colima"])
        let kubectlOk = binaryExists("kubectl", candidates: ["/opt/homebrew/bin/kubectl", "/usr/local/bin/kubectl"])
        let dockerCli = binaryExists("docker", candidates: ["/usr/local/bin/docker", "/opt/homebrew/bin/docker"])
        let dockerDesk = FileManager.default.fileExists(atPath: "/Applications/Docker.app")

        return Status(colima: colimaOk, kubectl: kubectlOk, docker: dockerCli, dockerDesktop: dockerDesk)
    }

    private static func binaryExists(_ name: String, candidates: [String]) -> Bool {
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) { return true }
        let which = ShellCapture.run("/usr/bin/which", args: [name])
        return !which.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
