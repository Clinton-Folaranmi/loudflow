import SwiftUI

struct Sidebar: View {
    @ObservedObject var model: AppModel

    private struct NavSpec { let tab: Tab; let label: String; let icon: String }
    private let navItems: [NavSpec] = [
        .init(tab: .today, label: "Today", icon: Solar.today),
        .init(tab: .library, label: "Library", icon: Solar.folder),
        .init(tab: .settings, label: "Settings", icon: Solar.settings),
        .init(tab: .receipts, label: "Receipts", icon: Solar.receipts),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Brand
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.logo).fill(Theme.sage)
                        .frame(width: 28, height: 28)
                    SolarIcon(name: Solar.mic, size: 16, color: Theme.card)
                }
                Text("LoudFlow")
                    .font(Typo.font(15, 800))
                    .tracking(-0.01 * 15)
                    .foregroundColor(Theme.ink)
            }

            // Nav
            VStack(alignment: .leading, spacing: 4) {
                ForEach(navItems, id: \.tab) { item in
                    NavRow(model: model, tab: item.tab, label: item.label, icon: item.icon,
                           count: count(for: item.tab))
                }
            }

            Spacer(minLength: 16)

            Rectangle().fill(Theme.hairline).frame(height: 1)

            // Storage
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    SolarIcon(name: Solar.database, size: 14, color: Theme.muted)
                    Text("ON THIS MAC")
                        .font(Typo.font(11, 700))
                        .tracking(0.08 * 11)
                        .foregroundColor(Theme.muted)
                }
                ProgressTrack(fraction: model.storageFraction, height: 6)
                Text(model.storageLabel)
                    .font(Typo.font(12, 400))
                    .foregroundColor(Theme.body)
            }

            // Version
            Text(Self.versionString)
                .font(Typo.font(10.5, 600))
                .foregroundColor(Theme.countInactive)
        }
        .padding(EdgeInsets(top: 20, leading: 16, bottom: 20, trailing: 16))
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.cardSmall).fill(Theme.card))
        .themeShadow(Theme.Shadow.card)
    }

    /// `LoudFlow 1.4.0 (10) · design 4` — the design version rides along with the build
    /// number while the design is in flux, so a stale build is visible at a glance.
    static var versionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "LoudFlow \(v) (\(b)) · design \(DesignVersion.current)"
    }

    private func count(for tab: Tab) -> String {
        switch tab {
        case .today:   return "\(model.todayClips.count)"
        case .library: return "\(model.clips.count)"
        default:       return ""
        }
    }
}

private struct NavRow: View {
    @ObservedObject var model: AppModel
    let tab: Tab
    let label: String
    let icon: String
    let count: String
    @State private var hovering = false

    private var active: Bool { model.tab == tab }

    var body: some View {
        HStack(spacing: 10) {
            SolarIcon(name: icon, size: 18, color: active ? Theme.sageDeep : Theme.body)
            Text(label)
                .font(Typo.font(13.5, active ? 700 : 400))
                .foregroundColor(active ? Theme.sageDeep : Theme.body)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(count)
                .font(Typo.font(11, 600))
                .foregroundColor(active ? Theme.sage : Theme.countInactive)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 11)
                .fill(active ? Theme.sagePale : (hovering ? Theme.sagePale2 : .clear))
        )
        .contentShape(RoundedRectangle(cornerRadius: 11))
        .onHover { hovering = $0 }
        .onTapGesture { model.tab = tab }
    }
}

