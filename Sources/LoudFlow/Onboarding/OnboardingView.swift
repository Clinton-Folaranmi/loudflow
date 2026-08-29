import SwiftUI

/// First-run onboarding, now **four** steps: mic check → trigger → **API key (required)** →
/// retention. The key step is net-new (added with the app owner's sign-off): nothing
/// transcribes without a key, so "Next" is disabled until one is entered.
struct OnboardingView: View {
    @ObservedObject var model: AppModel
    @State private var keyInput: String = ""

    private var step: Int { model.onboardingStep }
    private var isLast: Bool { step == AppModel.onboardingLastStep }

    private struct Copy { let kicker: String; let title: String; let body: String }
    private var copy: Copy {
        switch step {
        case 0: return Copy(kicker: "Step 1", title: "Say something.",
                            body: "Just checking your mic works. Nothing is recorded yet.")
        case 1: return Copy(kicker: "Step 2", title: "How do you want to record?",
                            body: "You can change this anytime.")
        case 2: return Copy(kicker: "Step 3", title: "Add your transcription key.",
                            body: "LoudFlow uses \(model.provider.displayName) to turn your voice into text. Paste your key to continue — nothing works without it.")
        default: return Copy(kicker: "Step 4", title: "How long to keep recordings?",
                             body: "Recordings stay on this Mac. Audio is sent to \(model.provider.displayName) to transcribe, then deleted there.")
        }
    }

    private var nextDisabled: Bool {
        step == 2 && !model.hasKey && keyInput.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ZStack {
            Color(hex: 0x1E261E, alpha: 0.5).ignoresSafeArea()
                .background(.ultraThinMaterial)     // approximates the blur(4px) scrim

            VStack(spacing: 0) {
                // Progress segments (4)
                HStack(spacing: 5) {
                    ForEach(0..<4, id: \.self) { i in
                        Capsule()
                            .fill(step >= i ? Theme.marigold : Theme.hairline)
                            .frame(height: 4)
                    }
                }
                .padding(EdgeInsets(top: 18, leading: 22, bottom: 0, trailing: 22))

                // Kicker / title / body
                VStack(alignment: .leading, spacing: 8) {
                    Text(copy.kicker).textStyle(.onboardingKicker).foregroundColor(Theme.marigoldInk)
                    Text(copy.title).textStyle(.onboardingTitle).foregroundColor(Theme.ink)
                    Text(copy.body).font(Typo.font(14.5, 400)).foregroundColor(Theme.body)
                        .lineSpacing(14.5 * 0.55)
                        .frame(maxWidth: 420, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 24, leading: 26, bottom: 6, trailing: 26))

                // Step content
                stepContent
                    .padding(EdgeInsets(top: 18, leading: 26, bottom: 0, trailing: 26))

                // Footer
                HStack(spacing: 10) {
                    Button { model.onboardingBack() } label: {
                        Text(step == 0 ? "Skip all this" : "Back")
                            .font(Typo.font(13.5, 700)).foregroundColor(Theme.muted)
                    }.buttonStyle(.plain)

                    Spacer()

                    Button(action: advance) {
                        Text(isLast ? "Start talking" : "Next")
                            .font(Typo.font(14, 800)).foregroundColor(Theme.cream)
                            .padding(.horizontal, 22).padding(.vertical, 11)
                            .background(Capsule().fill(Theme.ink))
                    }
                    .buttonStyle(.plain)
                    .disabled(nextDisabled)
                    .opacity(nextDisabled ? 0.5 : 1)
                }
                .padding(EdgeInsets(top: 22, leading: 26, bottom: 24, trailing: 26))
            }
            .frame(width: 540)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.onboarding).fill(Theme.card))
            .themeShadow(Theme.Shadow.onboarding)
            .transition(.fRise)
        }
        .animation(.easeOut(duration: 0.2), value: step)
    }

    private func advance() {
        if step == 2, !keyInput.trimmingCharacters(in: .whitespaces).isEmpty {
            model.saveKey(keyInput)
            keyInput = ""
        }
        model.onboardingNext()
    }

    // MARK: Step content

    @ViewBuilder private var stepContent: some View {
        switch step {
        case 0: micStep
        case 1: triggerStep
        case 2: keyStep
        default: retentionStep
        }
    }

    private var micStep: some View { MicTestView() }

    private var triggerStep: some View {
        VStack(spacing: 9) {
            ForEach(TriggerMode.allCases, id: \.self) { t in
                Button { model.selectTrigger(t) } label: {
                    HStack(spacing: 13) {
                        SolarIcon(name: t.iconName, size: 22, color: Theme.sage)
                        Keycap(text: t.combo, fg: Theme.body, bg: Theme.sagePale2,
                               radius: Theme.Radius.keycap, hPad: 10, vPad: 5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.name).font(Typo.font(14, 800)).foregroundColor(Theme.ink)
                            Text(t.desc).font(Typo.font(12.5, 400)).foregroundColor(Theme.muted)
                        }
                        Spacer()
                    }
                    .padding(EdgeInsets(top: 14, leading: 15, bottom: 14, trailing: 15))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .stroke(model.trigger == t ? Theme.marigold : Theme.hairline, lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var keyStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(Provider.allCases, id: \.self) { p in
                    Button { model.provider = p } label: {
                        Text(p.displayName)
                            .font(Typo.font(13, 700))
                            .foregroundColor(model.provider == p ? Theme.creamInk : Theme.body)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Capsule().fill(model.provider == p ? Theme.marigoldPale : Theme.sagePale2))
                            .overlay(Capsule().stroke(model.provider == p ? Theme.marigold : .clear, lineWidth: 1.5))
                    }.buttonStyle(.plain)
                }
                Spacer()
                if model.hasKey {
                    Text("Key saved").font(Typo.font(12.5, 700)).foregroundColor(Theme.sageDeep)
                }
            }
            SecureField(model.hasKey ? "•••••••••• (saved — paste to replace)" : "Paste your \(model.provider.displayName) API key", text: $keyInput)
                .textFieldStyle(.plain)
                .font(Typo.font(15, 400))
                .foregroundColor(Theme.ink)
                .padding(EdgeInsets(top: 13, leading: 15, bottom: 13, trailing: 15))
                .background(RoundedRectangle(cornerRadius: Theme.Radius.block).fill(Theme.cream))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.block).stroke(Theme.creamLine2, lineWidth: 1.5))
            Text("Stored in your Mac's Keychain. Zero-retention request; nothing is kept on the service.")
                .font(Typo.font(12.5, 400)).foregroundColor(Theme.muted)
        }
    }

    private var retentionStep: some View {
        VStack(spacing: 9) {
            ForEach(Retention.allCases, id: \.self) { r in
                Button { model.retention = r } label: {
                    HStack {
                        Text(r.label).font(Typo.font(14, 800)).foregroundColor(Theme.ink)
                        Spacer()
                        Text(r.note).font(Typo.font(12.5, 400)).foregroundColor(Theme.muted)
                    }
                    .padding(EdgeInsets(top: 14, leading: 15, bottom: 14, trailing: 15))
                    .background(RoundedRectangle(cornerRadius: 16)
                        .fill(model.retention == r ? Theme.marigoldPale : Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .stroke(model.retention == r ? Theme.marigold : Theme.hairline, lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Live mic test: real bars that move with your voice, and a label that confirms it hears you.
private struct MicTestView: View {
    @StateObject private var meter = MicMeter()

    var body: some View {
        HStack(spacing: 16) {
            LiveWaveBars(level: meter.level, height: 30, color: Theme.sage)
                .frame(maxWidth: .infinity)
            Text(meter.level > 0.1 ? "Hearing you" : "Say something…")
                .font(Typo.font(13, 800))
                .foregroundColor(Theme.sageDeep)
                .frame(width: 110, alignment: .leading)
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.block).fill(Theme.cream))
        .onAppear { meter.start() }
        .onDisappear { meter.stop() }
    }
}
