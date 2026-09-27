import Cocoa

MainActor.assumeIsolated {
    let delegate = AppDelegate()
    NSApplication.shared.delegate = delegate
    NSApplication.shared.setActivationPolicy(.accessory)
    NSApplication.shared.run()
}
