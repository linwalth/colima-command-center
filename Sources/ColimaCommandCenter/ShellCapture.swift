import Foundation

/// Captures stdout of a command (for healthcheck output parsing).
/// Inherits COLIMA_HOME injection from Shell.sync logic.
enum ShellCapture {
    /// Runs a process and captures stdout. Stderr discarded to avoid
    /// pipe-buffer deadlock. Kills the process after `timeout` seconds so a
    /// hung child (e.g. kubectl stuck on a dead socket) cannot freeze the
    /// caller indefinitely. Returns exitCode -2 on timeout, -1 on spawn error.
    static func run(_ path: String, args: [String] = [], timeout: TimeInterval = 30) -> (stdout: String, exitCode: Int32) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        proc.environment = AppPaths.enrichedEnvironment()
        let outPipe = Pipe()
        proc.standardOutput = outPipe
        // Redirect stderr to /dev/null to avoid pipe-buffer deadlock.
        // If /dev/null unavailable, share stdout pipe (stderr merges into stdout).
        let devNull = FileHandle(forWritingAtPath: "/dev/null")
        proc.standardError = devNull ?? outPipe
        do {
            try proc.run()
        } catch {
            devNull?.closeFile()
            return ("", -1)
        }
        // Watchdog: terminate on timeout so readDataToEndOfFile unblocks.
        // DispatchWorkItem (not asyncAfter) lets us cancel the watchdog after
        // the process exits naturally, releasing the proc/semaphore retain
        // cycle instead of holding them for the full timeout duration.
        // Kill the ENTIRE process group (negative PGID), not just the direct
        // child — colima ssh forks ssh/bash grandchildren that keep the pipe
        // write-end open, so proc.terminate() (SIGTERM to direct child only)
        // leaves readDataToEndOfFile blocked forever.
        let timedOut = DispatchSemaphore(value: 0)
        let watchdog = DispatchWorkItem {
            if proc.isRunning {
                kill(-proc.processIdentifier, SIGKILL)
                timedOut.signal()
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        watchdog.cancel()
        devNull?.closeFile()
        if timedOut.wait(timeout: .now()) == .success {
            return ("", -2)
        }
        return (String(data: data, encoding: .utf8) ?? "", proc.terminationStatus)
    }
}
