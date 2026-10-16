import AppKit

// The synchronous executable entry point runs on the main thread.
MainActor.assumeIsolated {
    let application = NSApplication.shared
    let appDelegate = AppDelegate()
    application.delegate = appDelegate
    application.setActivationPolicy(.accessory)

    // NSApplication keeps a weak delegate; retain it for the entire event loop.
    withExtendedLifetime(appDelegate) {
        application.run()
    }
}
