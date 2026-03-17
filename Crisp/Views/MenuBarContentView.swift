import ServiceManagement
import SwiftUI
import os

struct MenuBarContentView: View {
    var audioManager: AudioInputManager

    var body: some View {
        statusSection

        Divider()

        deviceSubmenu

        pauseToggle

        Divider()

        launchAtLoginToggle

        Divider()

        aboutButton
        quitButton
    }

    // MARK: - Sections

    private var statusSection: some View {
        Group {
            if audioManager.isPaused {
                Label("Paused", systemImage: "pause.circle")
                    .foregroundStyle(.secondary)
            } else if audioManager.isForcing {
                Label("Forcing…", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.orange)
            } else if let name = audioManager.forcedDeviceName {
                Label(name, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("No device selected", systemImage: "questionmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var deviceSubmenu: some View {
        Menu("Forced Input") {
            if audioManager.inputDevices.isEmpty {
                Text("No input devices found")
            } else {
                ForEach(audioManager.inputDevices) { device in
                    Toggle(device.name, isOn: Binding(
                        get: { device.id == audioManager.forcedDeviceID },
                        set: { isOn in
                            if isOn { audioManager.selectDevice(device) }
                        }
                    ))
                }
            }
        }
    }

    private var pauseToggle: some View {
        Toggle("Pause", isOn: Binding(
            get: { audioManager.isPaused },
            set: { _ in audioManager.togglePause() }
        ))
    }

    private var launchAtLoginToggle: some View {
        Toggle("Launch at Login", isOn: Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    Logger(subsystem: "com.aayush.crisp", category: "LoginItem")
                        .error("Failed to toggle login item: \(error)")
                }
            }
        ))
    }

    private var aboutButton: some View {
        Button("About Crisp") {
            NSApp.sendAction(#selector(AppDelegate.showAboutPanel), to: nil, from: nil)
        }
    }

    private var quitButton: some View {
        Button("Quit Crisp") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
