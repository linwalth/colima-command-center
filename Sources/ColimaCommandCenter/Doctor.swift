import Foundation

/// Doctor diagnostics — native, calls colima/kubectl directly.
/// Inspired by `ctl doctor`.
struct Doctor {
    static func run() -> (output: String, exitCode: Int32) {
        let result = ClusterOps.doctor()
        return (result.0, result.1)
    }
}
