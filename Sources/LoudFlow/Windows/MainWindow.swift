import SwiftUI

/// The normal app window: a sticky 212px sidebar and a content column on the tinted "desk".
/// Most tabs scroll as a page; Library fills the window height and scrolls internally.
/// Onboarding overlays this (see `RootView`).
struct MainWindow: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            Sidebar(model: model)
                .frame(width: 212)

            pane
        }
        // Small top inset — just enough to clear the floating traffic lights. The window
        // ignores the (hidden) title-bar safe area so this isn't doubled up.
        .padding(EdgeInsets(top: 16, leading: 26, bottom: 26, trailing: 26))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.desk)
        .ignoresSafeArea(.container, edges: .top)
    }

    /// Library owns its own scrolling — the clip list and the transcript each scroll on their
    /// own inside a viewport-height layout — so it is *not* wrapped in the page ScrollView.
    /// Every other tab is a growing column that scrolls as a whole.
    @ViewBuilder private var pane: some View {
        switch model.tab {
        case .library:
            LibraryView(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        default:
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.bottom, 150)   // clearance for the floating widget
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
