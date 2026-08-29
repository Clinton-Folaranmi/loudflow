import SwiftUI

/// The permanent home for the API key (the other entry point is onboarding step 3). Cream
/// card, styled to match Retention, placed directly below it. The key is saved to the
/// Keychain — never UserDefaults.
struct TranscriptionCard: View {
    @ObservedObject var model: AppModel
    @State private var keyInput: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                SolarIcon(name: Solar.key, size: 18, color: Theme.marigoldInk)
                Text("Transcription").font(Typo.font(15, 800)).foregroundColor(Theme.creamInk)
            }

            // Provider (Deepgram default; Whisper slots in behind the same protocol).
            HStack(spacing: 8) {
                ForEach(Provider.allCases, id: \.self) { p in
                    Button { model.provider = p; keyInput = "" } label: {
                        Text(p.displayName)
                            .font(Typo.font(13, 700))
                            .foregroundColor(model.provider == p ? Theme.creamInk : Theme.creamBody)
                            .padding(.horizontal, 16).padding(.vertical, 9)
                            .background(Capsule().fill(model.provider == p ? Theme.marigold : .clear))
                            .overlay(Capsule().stroke(model.provider == p ? Theme.marigold : Theme.creamLine, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Key field + save
            HStack(spacing: 8) {
                SecureField(model.hasKey ? "•••••••••• (saved)" : "Paste your \(model.provider.displayName) API key", text: $keyInput)
                    .textFieldStyle(.plain)
                    .font(Typo.font(14, 400))
                    .foregroundColor(Theme.ink)
                    .padding(EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14))
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.editor).fill(Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.editor).stroke(Theme.creamLine2, lineWidth: 1.5))

                Button {
                    model.saveKey(keyInput)
                    keyInput = ""
                    model.validateKey()
                } label: {
                    Text("Save")
                        .font(Typo.font(13, 800))
                        .foregroundColor(Theme.cream)
                        .padding(.horizontal, 18).padding(.vertical, 11)
                        .background(Capsule().fill(Theme.ink))
                }
                .buttonStyle(.plain)
                .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(keyInput.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)

                if model.hasKey {
                    Button { model.clearKey() } label: {
                        Text("Remove").font(Typo.font(13, 700)).foregroundColor(Theme.creamMuted)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 6) {
                Circle().fill(statusColor).frame(width: 7, height: 7)
                Text(statusText).font(Typo.font(12.5, 700)).foregroundColor(Theme.marigoldInk)
            }

            Text("Audio goes to \(model.provider.displayName) to be transcribed with a zero-retention request, then nothing is kept there. The key lives in your Mac's Keychain.")
                .font(Typo.font(12.5, 400))
                .foregroundColor(Theme.creamBody)
                .lineSpacing(12.5 * 0.4)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.cardSmall).fill(Theme.cream))
    }

    private var statusColor: Color {
        switch model.keyStatus {
        case .saved:    return Theme.sage
        case .checking: return Theme.marigold
        case .rejected: return Theme.danger
        case .missing:  return Theme.creamMuted
        }
    }

    private var statusText: String {
        switch model.keyStatus {
        case .saved:    return "Key saved."
        case .checking: return "Checking…"
        case .rejected: return "That key was rejected."
        case .missing:  return "No key yet — recordings will wait until you add one."
        }
    }
}
