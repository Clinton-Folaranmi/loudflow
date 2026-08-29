import SwiftUI

struct ReceiptsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Receipts").textStyle(.pageTitle).foregroundColor(Theme.ink)
                Text("Proof that talking to yourself is productive.")
                    .textStyle(.subtitle).foregroundColor(Theme.body)
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)

            HStack(alignment: .top, spacing: 14) {
                StatCard(icon: Solar.textField, label: "WORDS TODAY",
                         value: model.wordsTodayLabel, caption: "none of them typed",
                         style: .light)
                StatCard(icon: Solar.stopwatch, label: "TYPING AVOIDED",
                         value: model.minutesSaved, caption: "at \(model.wpm) words a minute",
                         style: .marigold)
                StatCard(icon: Solar.folder, label: "CLIPS STORED",
                         value: "\(model.clips.count)", caption: model.storageLabel,
                         style: .light)
            }

            wordsPerDayCard
        }
    }

    private var wordsPerDayCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Words per day").font(Typo.font(16, 800)).foregroundColor(Theme.ink)
                WeekChart(bars: weekBars, chartHeight: 170, gap: 16)
                Text(model.longestCaption)
                    .font(Typo.font(13, 400)).foregroundColor(Theme.body)
            }
        }
    }

    // Real per-day word counts for the last 7 days; the loudest day is the sage peak.
    private var weekBars: [ChartBar] {
        let week = model.weekWords
        let maxWords = max(1, week.map(\.words).max() ?? 1)
        return week.map { d in
            let peak = (d.words == maxWords && d.words > 0)
            return ChartBar(
                fraction: Double(d.words) / Double(maxWords),
                color: peak ? Theme.sage : Theme.desk,
                label: d.label,
                labelColor: peak ? Theme.sageDeep : Theme.muted,
                labelWeight: peak ? 800 : 700
            )
        }
    }
}

private struct StatCard: View {
    enum Style { case light, marigold }
    let icon: String
    let label: String
    let value: String
    let caption: String
    let style: Style

    private var bg: Color { style == .marigold ? Theme.marigold : Theme.card }
    private var labelColor: Color { style == .marigold ? Theme.marigoldInk2 : Theme.muted }
    private var valueColor: Color { style == .marigold ? Theme.creamInk : Theme.ink }
    private var captionColor: Color { style == .marigold ? Theme.creamInk : Theme.body }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                SolarIcon(name: icon, size: 14, color: labelColor)
                Text(label).font(Typo.font(11.5, 700)).tracking(0.08 * 11.5).foregroundColor(labelColor)
            }
            Text(value).textStyle(.statReceipts).foregroundColor(valueColor)
            Text(caption).font(Typo.font(13, 400)).foregroundColor(captionColor)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.cardSmall).fill(bg))
    }
}
