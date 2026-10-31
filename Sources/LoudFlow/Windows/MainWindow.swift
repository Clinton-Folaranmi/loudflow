import SwiftUI

struct MainWindow: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            Sidebar(model: model)
                .frame(width: 212)

            ZStack(alignment: .topLeading) {
                pane
                    .id(model.tab)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(reduceMotion ? nil : Motion.page, value: model.tab)
        }
        .padding(EdgeInsets(top: 16, leading: 26, bottom: 26, trailing: 26))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.desk)
        .ignoresSafeArea(.container, edges: .top)
    }

    @ViewBuilder private var pane: some View {
        switch model.tab {
        case .library:
            LibraryView(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        default:
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.bottom, 150)
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private var content: some View {
        switch model.tab {
        case .today:    TodayView(model: model)
        case .library:  LibraryView(model: model)
        case .settings: SettingsView(model: model)
        case .receipts: ReceiptsView(model: model)
        }
    }
}
