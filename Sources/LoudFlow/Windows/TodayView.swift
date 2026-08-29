import SwiftUI

struct TodayView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text(model.greeting).textStyle(.greeting).foregroundColor(Theme.ink)
                Text(model.subline).textStyle(.subtitle).foregroundColor(Theme.body)
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)

            TwoColumn(leftFr: 1.5, rightFr: 1) {
                recordingsCard
            } right: {
                savedTodayCard
            }
        }
    }

    private var recordingsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Today's recordings").font(Typo.font(16, 800)).foregroundColor(Theme.ink)
                    Spacer()
                    Button { model.tab = .library } label: {
                        HStack(spacing: 6) {
                            Text("Open library").font(Typo.font(12.5, 700)).foregroundColor(Theme.link)
                            SolarIcon(name: Solar.arrowRight, size: 13, color: Theme.link)
                        }
                    }
                    .buttonStyle(.plain)
                }

                if model.todayClips.isEmpty {
                    Text("Nothing yet today. Click the widget and talk.")
                        .font(Typo.font(14, 400))
                        .foregroundColor(Theme.placeholder)
                        .padding(.vertical, 8)
                } else {
                    ForEach(model.todayClips.prefix(4)) { clip in
                        ClipRowView(model: model, clip: clip, variant: .today)
                    }
                }
            }
        }
    }

    private var savedTodayCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SAVED TODAY")
                .font(Typo.font(11.5, 700))
                .tracking(0.1 * 11.5)
                .foregroundColor(Theme.inkMutedOnDark)
            Text(model.minutesSaved)
                .textStyle(.bigStat)
                .foregroundColor(Theme.inkOnDark)
            Text("of typing, at your own \(model.wpm) wpm")
                .font(Typo.font(13.5, 400))
                .foregroundColor(Theme.inkBodyOnDark)

            Rectangle().fill(Theme.dividerOnDark).frame(height: 1)
                .padding(.top, 12).padding(.bottom, 10)

            WeekChart(bars: weekBars, chartHeight: 64, gap: 7)

            Text(model.weekCaption)
                .font(Typo.font(12.5, 400))
                .foregroundColor(Theme.inkMutedOnDark)
                .padding(.top, 8)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.ink))
    }

    // Real per-day word counts for the last 7 days; the loudest day is the marigold peak.
    private var weekBars: [ChartBar] {
        let week = model.weekWords
        let maxWords = max(1, week.map(\.words).max() ?? 1)
        return week.map { d in
            ChartBar(
                fraction: Double(d.words) / Double(maxWords),
                color: (d.words == maxWords && d.words > 0) ? Theme.marigold : Theme.barOnDark
            )
        }
    }
}
