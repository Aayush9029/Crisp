import AppKit
import os
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var aboutWindow: NSWindow?
    private let logger = Logger(subsystem: "com.aayush.crisp", category: "AppDelegate")

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("Application launched")
    }

    @objc func showAboutPanel() {
        if let existing = aboutWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        NSApp.setActivationPolicy(.regular)

        let hostingView = NSHostingView(rootView: AboutView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 440),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        aboutWindow = window
        logger.info("About panel shown")
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === aboutWindow else { return }
        aboutWindow = nil
        NSApp.setActivationPolicy(.accessory)
    }
}
