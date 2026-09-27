import Foundation

/// Disk usage inspection + cleanup — native, calls colima/kubectl directly.
/// Inspired by `ctl disk` / `ctl disk --clean`.
struct DiskInspector {
    struct Block: Identifiable {
        let id = UUID()
        let title: String
        let raw: String
    }

    static func usage() -> [Block]? {
        guard let info = ClusterOps.diskUsage() else { return nil }
        return [
            Block(title: L10n.tr("disk.vm_disks"), raw: info.vmDisks.isEmpty ? L10n.tr("kube.empty_marker") : info.vmDisks),
            Block(title: L10n.tr("disk.pvcs"), raw: info.pvcs.isEmpty ? L10n.tr("kube.empty_marker") : info.pvcs),
            Block(title: L10n.tr("disk.pvc_usage"), raw: info.pvcUsage.isEmpty ? L10n.tr("kube.empty_marker") : info.pvcUsage),
            Block(title: L10n.tr("disk.docker_storage"), raw: info.dockerStorage.isEmpty ? L10n.tr("kube.empty_marker") : info.dockerStorage),
        ]
    }

    static func clean() -> String {
        ClusterOps.cleanDisk()
    }
}
