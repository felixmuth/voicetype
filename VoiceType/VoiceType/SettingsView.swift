import SwiftUI
import VoiceTypeCore

/// Einstellungen — vier Sektionen: Push-to-Talk-Hotkey-Capture, Sprache,
/// Text-Cleanup-Schalter (mit Verfügbarkeits-Hinweis), Login-at-Login.
struct SettingsView: View {
    @Bindable var controller: AppController
    @State private var isCapturingHotkey = false
    @State private var showLoginError = false

    var body: some View {
        Form {
            Section("Push-to-Talk") {
                HStack {
                    Text("Hotkey:")
                    Text(controller.settings.pushToTalkKey.uppercased())
                        .font(.body.monospaced())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    Spacer()
                    Button(isCapturingHotkey ? "Drücke eine Taste…" : "Drücke neue Taste…") {
                        startHotkeyCapture()
                    }
                    .disabled(isCapturingHotkey)
                }
            }

            Section {
                Picker("Sprache", selection: $controller.settings.language) {
                    Text("Automatisch").tag("auto")
                    Text("Deutsch").tag("de")
                    Text("Englisch").tag("en")
                }
                .pickerStyle(.menu)
            } footer: {
                Text("Wirkt beim nächsten App-Start.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Text aufpolieren (Apple Foundation Models)",
                       isOn: $controller.settings.cleanupEnabled)
                if let hint = controller.cleanupHint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } footer: {
                Text("Wirkt beim nächsten App-Start.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Start") {
                Toggle("Beim Login starten",
                       isOn: $controller.settings.launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Einstellungen")
        .onDisappear {
            // Verhindert Zombie-Capture-Monitore, wenn der User die View
            // verlässt, ohne eine Taste gedrückt zu haben.
            if isCapturingHotkey {
                controller.cancelHotkeyCapture()
                isCapturingHotkey = false
            }
        }
        .onChange(of: controller.loginErrorMessage) { _, new in
            showLoginError = (new != nil)
        }
        .alert("Anmeldeobjekt konnte nicht gesetzt werden",
               isPresented: $showLoginError) {
            Button("OK") { controller.loginErrorMessage = nil }
        } message: {
            Text(controller.loginErrorMessage ?? "")
        }
    }

    private func startHotkeyCapture() {
        isCapturingHotkey = true
        controller.hotkeyCaptureBegin { newName in
            controller.settings.pushToTalkKey = newName
            isCapturingHotkey = false
        }
    }
}
