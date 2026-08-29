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
                // 112pt of headroom so the tallest bar's hover panel never covers the heading.
                chart.padding(.top, 112)
                Text(model.longestCaption)
                    .font(Typo.font(13, 400)).foregroundColor(Theme.body)
            }
        }
    }

    /// The week's bars, each one its own hover target. Hovering turns the bar marigold and
    /// floats the day's detail above it — anchored to the bar, so the panel tracks the day's
    /// height instead of sitting at a fixed line.
    private var chart: some View {
        let week = model.weekWords
        let maxWords = max(1, week.map(\.words).max() ?? 1)

        return HStack(alignment: .top, spacing: 16) {
            ForEach(Array(week.enumerated()), id: \.element.id) { index, day in
                DayColumn(
                    day: day,
                    fraction: Double(day.words) / Double(maxWords),
                    chartHeight: 170,
                    peak: day.words == maxWords && day.words > 0,
                    typingWPM: model.typingWPM,
                    panelEdge: index == 0 ? .leading : (index == week.count - 1 ? .trailing : .center)
                )
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// One day of the chart: the bar, its weekday label, and the detail panel on hover.
private struct DayColumn: View {
    let day: AppModel.DayWords
    let fraction: Double
    let chartHeight: CGFloat
    let peak: Bool
    let typingWPM: Int
    let panelEdge: PanelEdge

    enum PanelEdge { case leading, center, trailing }

    @State private var hovering = false

    private var barHeight: CGFloat { max(2, chartHeight * fraction) }
    private var barColor: Color { hovering ? Theme.marigold : (peak ? Theme.sage : Theme.desk) }

    private var alignment: Alignment {
        switch panelEdge {
        case .leading:  return .bottomLeading
        case .center:   return .bottom
        case .trailing: return .bottomTrailing
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottom) {
                Color.clear.frame(maxWidth: .infinity).frame(height: chartHeight)
                UnevenRoundedRectangle(topLeadingRadius: Theme.Radius.bar,
                                       topTrailingRadius: Theme.Radius.bar)
                    .fill(barColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: barHeight)
                    .animation(.easeInOut(duration: 0.12), value: hovering)
            }
            .overlay(alignment: alignment) {
                if hovering {
                    panel.offset(y: -(barHeight + 8))
                }
            }
            Text(day.label)
                .font(Typo.font(12, peak ? 800 : 700))
                .foregroundColor(peak ? Theme.sageDeep : Theme.muted)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(day.words) words")
                .font(Typo.font(15, 800)).foregroundColor(Theme.marigold)
            Text("\(day.minutesSaved(typingWPM: typingWPM)) min of typing avoided")
                .font(Typo.font(12, 700)).foregroundColor(Theme.inkOnDark)
            Text(day.recordingsLine)
                .font(Typo.font(12, 400)).foregroundColor(Theme.inkMutedOnDark)
            Text(day.longestLine)
                .font(Typo.font(12, 400)).foregroundColor(Theme.inkMutedOnDark)
        }
        .frame(width: 184, alignment: .leading)
        .padding(.horizontal, 13).padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.editor).fill(Theme.ink))
        .shadow(color: Color(hex: 0x141C14, alpha: 0.28), radius: 18, x: 0, y: 6)
        .allowsHitTesting(false)
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
