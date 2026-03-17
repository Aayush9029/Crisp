import os
import SwiftUI

@main
struct CrispApp: App {
    @State private var audioManager = AudioInputManager()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let logger = Logger(subsystem: "com.aayush.crisp", category: "App")

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        logger.info("Crisp initialized")
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(audioManager: audioManager)
        } label: {
            Label(
                "Crisp",
                systemImage: audioManager.isPaused
                    ? "airpodspro.chargingcase.wireless"
                    : "airpodspro.chargingcase.wireless.fill"
            )
        }
        .menuBarExtraStyle(.menu)
    }
}
