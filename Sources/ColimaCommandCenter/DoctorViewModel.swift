import Cocoa
import SwiftUI

@MainActor
final class DoctorViewModel: ObservableObject {
    @Published var output: String = ""
    @Published var isRunning = false
    @Published var hasRun = false
    @Published var showConfirm = false
    @Published var failed = false

    func runDoctor() {
        isRunning = true
        output = ""
        failed = false
        diagLog("[Doctor] starting runDoctor()")
        Task {
            diagLog("[Doctor] detached task started")
            let result = await Task.detached(priority: .userInitiated) { Doctor.run() }.value
            diagLog("[Doctor] task completed: exitCode=\(result.exitCode)")
            self.output = result.output
            self.failed = result.exitCode != 0
            self.isRunning = false
            self.hasRun = true
            diagLog("[Doctor] UI state set: isRunning=\(self.isRunning)")
        }
    }

    private func diagLog(_ msg: String) {
        let path = NSTemporaryDirectory() + "ccc-doctor-diag.log"
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "\(ts) \(msg)\n"
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            handle.closeFile()
        } else {
            FileManager.default.createFile(atPath: path, contents: Data(line.utf8))
        }
    }
}
