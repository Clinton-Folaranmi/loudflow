import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings").textStyle(.pageTitle).foregroundColor(Theme.ink)
                Text("Set your preferences")
                    .textStyle(.subtitle).foregroundColor(Theme.body)
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)

            nameCard
            triggerGrid
            toggleCard
            retentionCard
            transcriptionCard          // new — the API key lives here (and in onboarding)
        }
    }

    // MARK: Name

    private var nameCard: some View {
        HStack(spacing: 12) {
            Text("What should I call you?").font(Typo.font(14.5, 700)).foregroundColor(Theme.ink)
            Spacer()
            TextField(model.systemFirstName, text: $model.displayName)
                .textFieldStyle(.plain)
                .font(Typo.font(14, 600))
                .foregroundColor(Theme.ink)
                .multilineTextAlignment(.trailing)
                .frame(width: 170)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.row))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline, lineWidth: 1))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.cardSmall).fill(Theme.card))
        .themeShadow(Theme.Shadow.card)
    }

    // MARK: Trigger cards

    private var triggerGrid: some View {
        HStack(spacing: 14) {
            ForEach(TriggerMode.allCases, id: \.self) { t in
                TriggerCard(mode: t, selected: model.trigger == t) { model.selectTrigger(t) }
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Toggles

    private struct OptionRow { let title: String; let hint: String; let keyPath: WritableKeyPath<DictationOptions, Bool> }
    private let optionRows: [OptionRow] = [
        .init(title: "Type it into whatever field I'm in", hint: "Off means it only lands on the clipboard.", keyPath: \.insert),
        .init(title: "Keep the audio, not just the text", hint: "So you can hear what you actually said.", keyPath: \.keep),
        .init(title: "Add punctuation", hint: "Commas and full stops. No rephrasing, ever.", keyPath: \.punct),
    ]

    private var toggleCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(optionRows.enumerated()), id: \.offset) { idx, row in
                Button { model.options[keyPath: row.keyPath].toggle() } label: {
                    HStack(spacing: 18) {
                        Text(row.title).font(Typo.font(14.5, 700)).foregroundColor(Theme.ink)
                        Spacer()
                        LFToggle(isOn: model.options[keyPath: row.keyPath])
                    }
                    .padding(.vertical, 15)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .bottom) {
                    if idx < optionRows.count - 1 {
                        Rectangle().fill(Theme.hairline2).frame(height: 1)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.cardSmall).fill(Theme.card))
        .themeShadow(Theme.Shadow.card)
    }

    // MARK: Retention

    private var retentionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                SolarIcon(name: Solar.history, size: 18, color: Theme.marigoldInk)
                Text("Keep recordings for").font(Typo.font(15, 800)).foregroundColor(Theme.creamInk)
            }
            HStack(spacing: 8) {
                ForEach(Retention.allCases, id: \.self) { r in
                    RetentionPill(label: r.label, selected: model.retention == r) { model.retention = r; model.sweepRetention() }
                }
            }
            Text(model.retention.settingsNote)
                .font(Typo.font(12.5, 400))
                .foregroundColor(Theme.marigoldInk)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.cardSmall).fill(Theme.cream))
    }

    // MARK: Transcription (new)

    private var transcriptionCard: some View { TranscriptionCard(model: model) }
}

// MARK: - Trigger card

private struct TriggerCard: View {
    let mode: TriggerMode
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                SolarIcon(name: mode.iconName, size: 19, color: Theme.sage)
                Text(mode.name).font(Typo.font(14.5, 800)).foregroundColor(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Keycap(text: mode.combo, fg: Theme.body, bg: Theme.sagePale2, radius: Theme.Radius.keycap)
            }
            .padding(EdgeInsets(top: 16, leading: 17, bottom: 16, trailing: 17))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.block).fill(Theme.card))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.block)
                    .stroke(selected ? Theme.marigold : Theme.hairline, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Retention pill

private struct RetentionPill: View {
    let label: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Typo.font(13, 700))
                .foregroundColor(selected ? Theme.creamInk : Theme.creamBody)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(Capsule().fill(selected ? Theme.marigold : Color.clear))
                .overlay(Capsule().stroke(selected ? Theme.marigold : Theme.creamLine, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}
