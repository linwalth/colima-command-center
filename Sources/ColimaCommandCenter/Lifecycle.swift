import Foundation

struct AppPaths {
    static let colima = "/opt/homebrew/bin/colima"

    /// True if colima binary is installed and runnable.
    static var colimaInstalled: Bool {
        if FileManager.default.isExecutableFile(atPath: colima) { return true }
        if FileManager.default.isExecutableFile(atPath: "/usr/local/bin/colima") { return true }
        let which = ShellCapture.run("/usr/bin/which", args: ["colima"])
        return !which.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// True if a colima config directory exists anywhere (XDG or ~/.colima).
    static var colimaInitialized: Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if FileManager.default.fileExists(atPath: "\(home)/.config/colima") { return true }
        if FileManager.default.fileExists(atPath: "\(home)/.colima") { return true }
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"],
           !xdg.isEmpty, FileManager.default.fileExists(atPath: "\(xdg)/colima") { return true }
        return false
    }

    /// Resolve bash: prefer Homebrew bash 5+ (supports associative arrays),
    /// fall back to system /bin/bash (3.2, limited).
    static var bash: String {
        for candidate in ["/opt/homebrew/bin/bash", "/usr/local/bin/bash"] {
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return "/bin/bash"
    }

    /// Resolve the colima home directory.
    /// Preference: if ~/.config/colima (or $XDG_CONFIG_HOME/colima) exists,
    /// force it via COLIMA_HOME so the app and CLI agree on XDG.
    /// Otherwise return nil — let colima resolve natively (default ~/.colima).
    /// Ref: https://colima.run/docs/faq/ — COLIMA_HOME default is $HOME/.colima.
    static var colimaHome: String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? "\(home)/.config"
        let xdgColima = "\(xdg)/colima"
        if FileManager.default.fileExists(atPath: xdgColima) {
            return xdgColima
        }
        return nil
    }

    /// Environment for spawned processes (colima/kubectl/etc.).
    ///
    /// Apps launched from Finder/Dock/Spotlight inherit launchd's minimal PATH
    /// (/usr/bin:/bin:/usr/sbin:/sbin) which OMITS Homebrew. Without it colima
    /// fatals with "lima not found" (limactl lives in /opt/homebrew/bin) and
    /// `colima status` returns nonzero — which the app misreads as "stopped".
    /// Prepend the Homebrew bin dirs (ARM + Intel) so colima/kubectl helpers
    /// resolve. Dedup preserves order. Also injects COLIMA_HOME.
    /// Ref: https://github.com/delibae/claude-prism/issues/87
    static func enrichedEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let hbDirs = ["/opt/homebrew/bin", "/usr/local/bin"]
            .filter { FileManager.default.isExecutableFile(atPath: $0) }
        if !hbDirs.isEmpty {
            let existing = (env["PATH"] ?? "").components(separatedBy: ":")
            var seen = Set(existing)
            var ordered = hbDirs.filter { !seen.contains($0) }
            seen.formUnion(hbDirs)
            ordered.append(contentsOf: existing)
            env["PATH"] = ordered.joined(separator: ":")
        }
        if let ch = colimaHome { env["COLIMA_HOME"] = ch }
        return env
    }

    static var colimaConfig: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if let ch = colimaHome {
            return "\(ch)/\(colimaProfile)/colima.yaml"
        }
        // Native colima resolution: ~/.colima if it exists, else ~/.config/colima.
        let dotColima = "\(home)/.colima/\(colimaProfile)/colima.yaml"
        if FileManager.default.fileExists(atPath: dotColima) {
            return dotColima
        }
        let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? "\(home)/.config"
        return "\(xdg)/colima/\(colimaProfile)/colima.yaml"
    }

    /// The colima profile this app manages. Currently hardcoded to "default";
    /// derive from COLIMA_PROFILE env if set (future multi-profile support).
    static var colimaProfile: String {
        ProcessInfo.processInfo.environment["COLIMA_PROFILE"] ?? "default"
    }
}

final class Lifecycle {
    static let shared = Lifecycle()
    private init() {}

    private var toggleInProgress = false
    private let lock = NSLock()

    /// Synchronous quick status check for use in collectors.
    /// Parses `colima list` — always fast, no SSH probing.
    func quickCheckRunning() -> Bool {
        let profile = AppPaths.colimaProfile
        let result = ShellCapture.run(AppPaths.colima, args: ["list"], timeout: 15)
        return result.stdout
            .components(separatedBy: "\n")
            .dropFirst()
            .contains { line in
                let cols = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).filter { !$0.isEmpty }
                guard cols.first == Substring(profile) else { return false }
                return line.range(of: "\\bRunning\\b", options: .regularExpression) != nil
            }
    }

    func checkStatus(completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            // Use `colima list` instead of `colima status`: it always returns
            // RC=0 promptly (no SSH/socket probing that can hang on a stale
            // socket during VM shutdown). Parse the STATUS column for OUR
            // profile only — supports multi-profile setups where another
            // profile may be running while ours is stopped.
            let profile = AppPaths.colimaProfile
            let result = ShellCapture.run(AppPaths.colima, args: ["list"], timeout: 15)
            let running = result.stdout
                .components(separatedBy: "\n")
                .dropFirst()
                .contains { line in
                    let cols = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).filter { !$0.isEmpty }
                    guard cols.first == Substring(profile) else { return false }
                    return line.range(of: "\\bRunning\\b", options: .regularExpression) != nil
                }
            completion(running)
        }
    }

    func toggle(completion: @escaping (_ wasRunning: Bool, _ exitCode: Int32) -> Void) {
        lock.lock()
        if toggleInProgress { lock.unlock(); completion(false, -1); return }
        toggleInProgress = true
        lock.unlock()

        checkStatus { running in
            let rc: Int32
            if running {
                rc = ClusterOps.shutdown()
            } else {
                rc = ClusterOps.startup()
            }
            self.lock.lock()
            self.toggleInProgress = false
            self.lock.unlock()
            completion(running, rc)
        }
    }

    /// Toggle with live stdout streaming via a callback.
    func toggleStream(onOutput: @escaping (String) -> Void,
                      completion: @escaping (_ wasRunning: Bool, _ exitCode: Int32) -> Void) {
        lock.lock()
        if toggleInProgress { lock.unlock(); completion(false, -1); return }
        toggleInProgress = true
        lock.unlock()

        checkStatus { running in
            let rc: Int32
            if running {
                rc = ClusterOps.shutdownStream(onOutput: onOutput)
            } else {
                rc = ClusterOps.startupStream(onOutput: onOutput)
            }
            self.lock.lock()
            self.toggleInProgress = false
            self.lock.unlock()
            completion(running, rc)
        }
    }

    /// Explicit start — ignores cached status, always starts the VM.
    /// Guards against double-start (noop if already running).
    func startStream(onOutput: @escaping (String) -> Void,
                     completion: @escaping (_ wasAlreadyRunning: Bool, _ exitCode: Int32) -> Void) {
        lock.lock()
        if toggleInProgress { lock.unlock(); completion(true, -1); return }
        toggleInProgress = true
        lock.unlock()

        checkStatus { running in
            if running {
                self.lock.lock()
                self.toggleInProgress = false
                self.lock.unlock()
                completion(true, 0)
                return
            }
            let rc = ClusterOps.startupStream(onOutput: onOutput)
            self.lock.lock()
            self.toggleInProgress = false
            self.lock.unlock()
            completion(false, rc)
        }
    }

    /// Explicit stop — ignores cached status, always stops the VM.
    /// Guards against double-stop (noop if already stopped).
    func stopStream(onOutput: @escaping (String) -> Void,
                    completion: @escaping (_ wasAlreadyStopped: Bool, _ exitCode: Int32) -> Void) {
        lock.lock()
        if toggleInProgress { lock.unlock(); completion(true, -1); return }
        toggleInProgress = true
        lock.unlock()

        checkStatus { running in
            if !running {
                self.lock.lock()
                self.toggleInProgress = false
                self.lock.unlock()
                completion(true, 0)
                return
            }
            let rc = ClusterOps.shutdownStream(onOutput: onOutput)
            self.lock.lock()
            self.toggleInProgress = false
            self.lock.unlock()
            completion(false, rc)
        }
    }

    // Non-streaming convenience wrappers (for menubar — no log panel).
    func start(completion: @escaping (_ wasAlreadyRunning: Bool, _ exitCode: Int32) -> Void) {
        startStream(onOutput: { _ in }, completion: completion)
    }
    func stop(completion: @escaping (_ wasAlreadyStopped: Bool, _ exitCode: Int32) -> Void) {
        stopStream(onOutput: { _ in }, completion: completion)
    }

    /// Explicit restart: stop then start, ignoring cached status.
    /// Unlike toggle, this never accidentally reverses direction if the VM
    /// state changed between the prompt appearing and the user confirming.
    func restart(completion: @escaping (_ exitCode: Int32) -> Void) {
        stopStream(onOutput: { _ in }) { wasAlreadyStopped, stopRC in
            if stopRC != 0 && !wasAlreadyStopped {
                completion(stopRC)
                return
            }
            self.startStream(onOutput: { _ in }) { _, startRC in
                completion(startRC)
            }
        }
    }
}

enum Shell {
    /// Runs a process synchronously, discarding output to /dev/null to avoid
    /// pipe-buffer deadlock on large outputs. Forces COLIMA_HOME to the XDG
    /// config dir so GUI-launched colima calls never recreate ~/.colima.
    static func sync(_ path: String, args: [String] = []) -> Int32 {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        proc.environment = AppPaths.enrichedEnvironment()
        let devNull = FileHandle(forWritingAtPath: "/dev/null")
        proc.standardOutput = devNull
        proc.standardError = devNull
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            devNull?.closeFile()
            return -1
        }
        devNull?.closeFile()
        return proc.terminationStatus
    }

    /// Streams stdout line-by-line via callback. Kills the process after
    /// `timeout` seconds (default 300s — generous for colima start/stop which
    /// can legitimately take minutes). Returns -2 on timeout.
    static func stream(_ path: String, args: [String] = [],
                        timeout: TimeInterval = 300,
                        onOutput: @escaping (String) -> Void) -> Int32 {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        proc.environment = AppPaths.enrichedEnvironment()
        let pipe = Pipe()
        proc.standardOutput = pipe
        let devNull = FileHandle(forWritingAtPath: "/dev/null")
        proc.standardError = devNull ?? pipe

        var buffer = Data()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            buffer.append(chunk)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer.prefix(upTo: nl + 1)
                buffer.removeSubrange(buffer.startIndex...nl)
                if let line = String(data: lineData, encoding: .utf8) {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { onOutput(trimmed) }
                }
            }
        }

        do {
            try proc.run()
        } catch {
            devNull?.closeFile()
            return -1
        }
        // Watchdog: terminate on timeout so waitUntilExit unblocks.
        // Kill entire process group — colima start/stop fork grandchildren
        // that keep pipes open, blocking readabilityHandler forever.
        let timedOut = DispatchSemaphore(value: 0)
        let watchdog = DispatchWorkItem {
            if proc.isRunning {
                kill(-proc.processIdentifier, SIGKILL)
                timedOut.signal()
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)
        proc.waitUntilExit()
        pipe.fileHandleForReading.readabilityHandler = nil
        // Flush remaining buffer.
        if !buffer.isEmpty, let rest = String(data: buffer, encoding: .utf8) {
            let trimmed = rest.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { onOutput(trimmed) }
        }
        devNull?.closeFile()
        watchdog.cancel()
        if timedOut.wait(timeout: .now()) == .success { return -2 }
        return proc.terminationStatus
    }

    /// Like sync() but kills the process if it exceeds `timeout` seconds.
    /// Returns -2 on timeout.
    static func syncWithTimeout(_ path: String, args: [String] = [], timeout: TimeInterval) -> Int32 {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        proc.environment = AppPaths.enrichedEnvironment()
        let devNull = FileHandle(forWritingAtPath: "/dev/null")
        proc.standardOutput = devNull
        proc.standardError = devNull
        do {
            try proc.run()
        } catch {
            devNull?.closeFile()
            return -1
        }
        // Deadline timer on a background queue.
        let deadline = DispatchTime.now() + timeout
        let timedOut = DispatchSemaphore(value: 0)
        let watchdog = DispatchWorkItem {
            if proc.isRunning {
                kill(-proc.processIdentifier, SIGKILL)
                timedOut.signal()
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: deadline, execute: watchdog)
        proc.waitUntilExit()
        devNull?.closeFile()
        watchdog.cancel()
        // If semaphore was signaled within timeout, we killed it.
        if timedOut.wait(timeout: .now()) == .success { return -2 }
        return proc.terminationStatus
    }
}
