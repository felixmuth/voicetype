import SwiftUI
import VoiceTypeCore

/// Einstellungen im Atelier-Stil.
///
/// Funktionalität unverändert ggü. Plan 4 — Push-to-Talk, Sprache,
/// Spracherkennungs-Engine (Apple/WhisperKit + Modell-Picker),
/// Cleanup-Engine, Login. Engine-/Modell-Picker triggern bei
/// fehlendem Modell einen Confirmation-Dialog + on-demand Download.
///
/// Visuell: ScrollView mit LazyVStack, jede Zeile als Compact-Row
/// (Name + Beschreibung links, Control rechts), Hairlines dazwischen,
/// Section-Header in Mono-Eyebrow-Style.
struct SettingsView: View {
    @Bindable var controller: AppController
    @State private var isCapturingHotkey = false
    @State private var showLoginError = false

    /// Vom Confirmation-Dialog gehaltener Pending-Download.
    @State private var pendingDownload: PendingDownload?

    struct PendingDownload {
        let descriptor: ModelDescriptor
        /// Wendet die Setting-Änderung an, wenn der Nutzer „Laden"
        /// bestätigt — und triggert dann den Download.
        let apply: () -> Void
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // ===== Push-to-Talk =====
                sectionHeader("Push-to-Talk")
                hotkeyRow

                // ===== Sprache =====
                sectionHeader("Sprache")
                languageRow

                // ===== Spracherkennung =====
                sectionHeader("Spracherkennung")
                transcriptionRows

                // ===== Text aufpolieren =====
                sectionHeader("Text aufpolieren")
                cleanupRows

                // ===== Erscheinungsbild =====
                sectionHeader("Erscheinungsbild")
                appearanceRow
                livePreviewRow

                // ===== Start =====
                sectionHeader("Start")
                loginRow
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 40)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .tint(Theme.plum)
        .onDisappear {
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
        .confirmationDialog(
            downloadDialogTitle,
            isPresented: Binding(
                get: { pendingDownload != nil },
                set: { if !$0 { pendingDownload = nil } }),
            titleVisibility: .visible
        ) {
            Button("Laden") { confirmDownload() }
            Button("Abbrechen", role: .cancel) { pendingDownload = nil }
        } message: {
            if let p = pendingDownload {
                Text("\(p.descriptor.displayName) (\(humanSize(p.descriptor.approxSizeBytes))) wird einmalig aus dem Internet heruntergeladen und lokal gespeichert. Bis es bereit ist, bleibt die aktuelle Engine aktiv.")
            }
        }
    }

    // MARK: - Section-Header

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(Theme.mono(10, weight: .medium))
            .tracking(1.6)
            .foregroundStyle(Theme.plum)
            .padding(.top, 28)
            .padding(.bottom, 10)
    }

    // MARK: - Row helpers

    private func settingRow<Control: View>(
        name: String,
        description: String? = nil,
        hint: String? = nil,
        hintColor: Color = .secondary,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(Theme.ui(13.5, weight: .medium))
                    .foregroundStyle(.primary)
                if let description {
                    Text(description)
                        .font(Theme.ui(12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let hint {
                    Text(hint)
                        .font(Theme.mono(10.5))
                        .foregroundStyle(hintColor)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            control()
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: - Push-to-Talk

    private var hotkeyRow: some View {
        settingRow(
            name: "Hotkey",
            description: "Halten zum Aufnehmen, loslassen zum Einfügen."
        ) {
            HStack(spacing: 10) {
                Text(controller.settings.pushToTalkKey.uppercased())
                    .font(Theme.mono(12, weight: .medium))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.06)))
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                    }

                Button(isCapturingHotkey ? "Drücke eine Taste…" : "Ändern") {
                    startHotkeyCapture()
                }
                .buttonStyle(AtelierButtonStyle())
                .disabled(isCapturingHotkey)
            }
        }
    }

    // MARK: - Sprache

    private var languageRow: some View {
        settingRow(
            name: "Sprache",
            description: "Automatisch erkennt Deutsch und Englisch im Wechsel.",
            hint: "wirkt beim nächsten App-Start"
        ) {
            AtelierMenu(
                current: controller.settings.language,
                options: [
                    ("auto", "Automatisch"),
                    ("de", "Deutsch"),
                    ("en", "Englisch")
                ],
                onSelect: { controller.settings.language = $0 })
        }
    }

    // MARK: - Spracherkennung

    @ViewBuilder
    private var transcriptionRows: some View {
        settingRow(
            name: "Engine",
            description: nil,
            hint: transcriptionFooter
        ) {
            AtelierMenu(
                current: controller.settings.transcriptionEngine,
                options: [
                    (.apple,      "Apple Speech"),
                    (.whisperKit, "WhisperKit (lokal)"),
                    (.parakeet,   "Parakeet (lokal)")
                ],
                onSelect: { handleTranscriptionPick($0) })
        }

        if controller.settings.transcriptionEngine == .whisperKit {
            settingRow(
                name: "Modell",
                description: nil
            ) {
                AtelierMenu(
                    current: controller.settings.whisperKitModelId,
                    options: ModelCatalog.whisperKitAll.map {
                        ($0.id, $0.displayName)
                    },
                    onSelect: { controller.settings.whisperKitModelId = $0 })
            }

            if let desc = ModelCatalog.whisperKit(id: controller.settings.whisperKitModelId) {
                // ModelStatusView reicht eine ganze Zeile — wir umgeben
                // sie mit derselben vertikalen Padding + Divider wie
                // settingRow, damit das Layout konsistent bleibt.
                VStack {
                    ModelStatusView(descriptor: desc, registry: controller.registry)
                }
                .padding(.vertical, 14)
                .overlay(alignment: .top) { Divider() }
            }
        }

        if controller.settings.transcriptionEngine == .parakeet {
            settingRow(
                name: "Modell",
                description: nil
            ) {
                AtelierMenu(
                    current: controller.settings.parakeetModelId,
                    options: ModelCatalog.parakeetAll.map {
                        ($0.id, $0.displayName)
                    },
                    onSelect: { controller.settings.parakeetModelId = $0 })
            }

            if let desc = ModelCatalog.parakeet(id: controller.settings.parakeetModelId) {
                VStack {
                    ModelStatusView(descriptor: desc, registry: controller.registry)
                }
                .padding(.vertical, 14)
                .overlay(alignment: .top) { Divider() }
            }
        }
    }

    // MARK: - Cleanup

    @ViewBuilder
    private var cleanupRows: some View {
        settingRow(
            name: "Cleanup-Engine",
            description: "Räumt Füllwörter, Zeichensetzung und Groß-/Kleinschreibung auf.",
            hint: cleanupFooter,
            hintColor: controller.cleanupHint != nil ? Theme.warn : .secondary
        ) {
            AtelierMenu(
                current: controller.settings.cleanupEngine,
                options: [
                    (.off,                    "Aus"),
                    (.appleFoundationModels,  "Apple Foundation Models"),
                    (.mlx,                    "Lokales LLM (MLX)")
                ],
                onSelect: { handleCleanupPick($0) })
        }

        if controller.settings.cleanupEngine == .mlx {
            settingRow(
                name: "Modell",
                description: nil
            ) {
                AtelierMenu(
                    current: controller.settings.mlxModelId,
                    options: ModelCatalog.mlxAll.map {
                        ($0.id, $0.displayName)
                    },
                    onSelect: { handleMLXModelPick($0) })
            }

            if let desc = ModelCatalog.mlx(id: controller.settings.mlxModelId) {
                VStack {
                    ModelStatusView(descriptor: desc, registry: controller.registry)
                }
                .padding(.vertical, 14)
                .overlay(alignment: .top) { Divider() }
            }
        }
    }

    /// MLX-Modellwechsel: bei nicht-installiertem Modell den Download-
    /// Dialog zeigen statt das Setting blind anzuwenden — sonst würde
    /// die Cleanup-Pipeline auf Passthrough fallen, ohne dass der User
    /// versteht warum.
    private func handleMLXModelPick(_ id: String) {
        guard let desc = ModelCatalog.mlx(id: id) else { return }
        askDownloadOrApply(descriptor: desc) {
            controller.settings.mlxModelId = id
        }
    }

    // MARK: - Erscheinungsbild

    private var appearanceRow: some View {
        settingRow(
            name: "Theme",
            description: "Hell, dunkel oder dem System folgen."
        ) {
            AtelierMenu(
                current: controller.settings.appearance,
                options: [
                    (.light,  "Hell"),
                    (.dark,   "Dunkel"),
                    (.system, "System")
                ],
                onSelect: { controller.settings.appearance = $0 })
        }
    }

    private var livePreviewRow: some View {
        settingRow(
            name: "Live-Vorschau",
            description: "Aufnahme-Overlay zeigt den diktierten Text mit. Ausgeschaltet bleibt nur ein kleiner Status-Kreis übrig."
        ) {
            Toggle("", isOn: $controller.settings.showLivePreview)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
    }

    // MARK: - Login

    private var loginRow: some View {
        settingRow(
            name: "Beim Login starten",
            description: "voicetype startet automatisch nach der Anmeldung am Mac."
        ) {
            Toggle("", isOn: $controller.settings.launchAtLogin)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
    }

    // MARK: - Picker-Handling (unverändert)

    private func handleTranscriptionPick(_ pick: TranscriptionEngineKind) {
        switch pick {
        case .apple:
            controller.settings.transcriptionEngine = .apple
        case .whisperKit:
            let desc = ModelCatalog.whisperKit(id: controller.settings.whisperKitModelId)
                ?? ModelCatalog.whisperKitDefault
            askDownloadOrApply(descriptor: desc) {
                controller.settings.whisperKitModelId = desc.id
                controller.settings.transcriptionEngine = .whisperKit
            }
        case .parakeet:
            let desc = ModelCatalog.parakeet(id: controller.settings.parakeetModelId)
                ?? ModelCatalog.parakeetDefault
            askDownloadOrApply(descriptor: desc) {
                controller.settings.parakeetModelId = desc.id
                controller.settings.transcriptionEngine = .parakeet
            }
        }
    }

    private func handleCleanupPick(_ pick: CleanupEngineKind) {
        switch pick {
        case .off, .appleFoundationModels:
            controller.settings.cleanupEngine = pick
        case .mlx:
            // Wenn das aktuell ausgewählte MLX-Modell noch nicht da ist,
            // den Download-Dialog zeigen — sonst würde Cleanup beim ersten
            // Diktat stillschweigend auf Passthrough fallen.
            let desc = ModelCatalog.mlx(id: controller.settings.mlxModelId)
                ?? ModelCatalog.mlxDefault
            askDownloadOrApply(descriptor: desc) {
                controller.settings.mlxModelId = desc.id
                controller.settings.cleanupEngine = .mlx
            }
        }
    }

    private func askDownloadOrApply(
        descriptor: ModelDescriptor, apply: @escaping () -> Void
    ) {
        switch controller.registry.status[descriptor] ?? .notInstalled {
        case .installed, .installing:
            apply()
        case .notInstalled, .failed:
            pendingDownload = PendingDownload(descriptor: descriptor, apply: apply)
        }
    }

    private func confirmDownload() {
        guard let p = pendingDownload else { return }
        p.apply()
        Task { await controller.registry.download(p.descriptor) }
        pendingDownload = nil
    }

    // MARK: - Footer (Plan 4 § 7.3)

    private var transcriptionFooter: String {
        let descriptor: ModelDescriptor?
        switch controller.settings.transcriptionEngine {
        case .whisperKit:
            descriptor = ModelCatalog.whisperKit(id: controller.settings.whisperKitModelId)
        case .parakeet:
            descriptor = ModelCatalog.parakeet(id: controller.settings.parakeetModelId)
        case .apple:
            descriptor = nil
        }
        return activationFooter(
            setting: controller.settings.transcriptionEngine,
            active: controller.appState.activeTranscriptionEngine,
            descriptor: descriptor,
            fallbackHint: controller.appState.engineFallbackHint)
    }

    private var cleanupFooter: String? {
        // Sonderfall „Aus": wenn die Einstellung .off ist und auch
        // tatsächlich .off läuft, würde der generische Footer „aktiv"
        // sagen — was wie „Cleanup ist an" klingt. Footer dann ganz weg.
        let setting = controller.settings.cleanupEngine
        let active = controller.appState.activeCleanupEngine
        if setting == .off && active == .off && controller.cleanupHint == nil {
            return nil
        }
        return activationFooter(
            setting: setting,
            active: active,
            descriptor: nil,
            fallbackHint: controller.cleanupHint)
    }

    private func activationFooter<E: Equatable>(
        setting: E, active: E,
        descriptor: ModelDescriptor?,
        fallbackHint: String?
    ) -> String {
        if setting == active { return "aktiv" }
        if let d = descriptor,
           case .installing = controller.registry.status[d] ?? .notInstalled {
            return "wird nach Download aktiv"
        }
        if isBusyDictating(controller.appState.dictationState) {
            return "wird nach aktuellem Diktat aktiv"
        }
        if let fallbackHint { return fallbackHint }
        return "wird sofort aktiv…"
    }

    private func isBusyDictating(_ state: DictationState) -> Bool {
        switch state {
        case .recording, .finalizing, .cleaning, .delivering: return true
        default: return false
        }
    }

    // MARK: - Hotkey-Capture (unverändert)

    private func startHotkeyCapture() {
        isCapturingHotkey = true
        controller.hotkeyCaptureBegin { newName in
            controller.settings.pushToTalkKey = newName
            isCapturingHotkey = false
        }
    }

    // MARK: - Misc

    private var downloadDialogTitle: String {
        guard let d = pendingDownload?.descriptor else { return "Modell laden?" }
        switch d.kind {
        case .whisperKit: return "WhisperKit-Modell laden?"
        case .mlx:        return "MLX-Modell laden?"
        case .parakeet:   return "Parakeet-Modell laden?"
        }
    }

    private func humanSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Atelier-Menu (Picker-Ersatz)

/// Schlankes Atelier-Dropdown. Rendert einen kompakten Button mit
/// aktuellem Wert + Chevron; beim Klick öffnet sich ein natives
/// `Menu` mit allen Optionen. Die aktuell ausgewählte Option wird
/// im Menü mit einem Häkchen markiert.
///
/// Generic über den `Value`-Typ — funktioniert mit String, Enums,
/// und allen Hashables.
struct AtelierMenu<Value: Hashable>: View {
    let current: Value
    let options: [(Value, String)]
    let onSelect: (Value) -> Void

    var body: some View {
        Menu {
            ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                Button {
                    onSelect(opt.0)
                } label: {
                    if opt.0 == current {
                        Label(opt.1, systemImage: "checkmark")
                    } else {
                        Text(opt.1)
                    }
                }
            }
        } label: {
            AtelierMenuLabel(text: currentLabel)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var currentLabel: String {
        options.first(where: { $0.0 == current })?.1 ?? "—"
    }
}

private struct AtelierMenuLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Text(text)
                .font(Theme.ui(12.5))
                .foregroundStyle(.primary)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.tight)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.tight)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Atelier-Button-Style

/// Knopf mit Plum-Outline. Wandelt bei Hover/Press die Outline auf
/// volle Plum-Fläche.
struct AtelierButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.mono(10.5, weight: .medium))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(
                isEnabled ? Theme.plum : Color.secondary
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.tight)
                    .fill(
                        configuration.isPressed
                            ? Theme.plum.opacity(0.12)
                            : Color.clear)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.tight)
                    .stroke(
                        isEnabled ? Theme.plum.opacity(0.55) : Color.secondary.opacity(0.3),
                        lineWidth: 0.7)
            }
    }
}
