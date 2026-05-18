import SwiftUI
import VoiceTypeCore

/// Modell-Status (installiert / lädt / fehlt / fehlgeschlagen) plus
/// passende Aktion. Atelier-Stil: Status-Icon mit Plum/Warn-Tönen,
/// schmaler ProgressView in Plum, Mono-Größenangaben.
struct ModelStatusView: View {
    let descriptor: ModelDescriptor
    let registry: ModelRegistry

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            switch registry.status[descriptor] ?? .notInstalled {

            case .notInstalled:
                statusIcon(systemName: "circle.dotted", color: .secondary)
                Text("Nicht installiert")
                    .font(Theme.ui(12.5))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Laden") {
                    Task { await registry.download(descriptor) }
                }
                .buttonStyle(AtelierButtonStyle())

            case .installing(let p):
                statusIcon(systemName: "arrow.down.circle", color: Theme.plum)
                ProgressView(value: p)
                    .progressViewStyle(.linear)
                    .tint(Theme.plum)
                    .frame(maxWidth: 140)
                Text("\(Int(p * 100)) %")
                    .font(Theme.mono(11))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Abbrechen") {
                    Task { await registry.cancelDownload(descriptor) }
                }
                .buttonStyle(AtelierButtonStyle())

            case .installed(let size):
                statusIcon(systemName: "checkmark.circle.fill", color: Theme.plum)
                Text("Installiert")
                    .font(Theme.ui(12.5))
                Text("(\(humanSize(size)))")
                    .font(Theme.mono(11))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Löschen") {
                    Task { try? await registry.delete(descriptor) }
                }
                .buttonStyle(AtelierButtonStyle())

            case .failed(let reason):
                statusIcon(systemName: "exclamationmark.triangle.fill", color: Theme.warn)
                Text(reason)
                    .font(Theme.ui(12))
                    .foregroundStyle(Theme.warn)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Button("Erneut laden") {
                    Task { await registry.download(descriptor) }
                }
                .buttonStyle(AtelierButtonStyle())
            }
        }
    }

    private func statusIcon(systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13))
            .foregroundStyle(color)
            .frame(width: 16)
    }

    private func humanSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
