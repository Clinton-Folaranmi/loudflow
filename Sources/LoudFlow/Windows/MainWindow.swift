import SwiftUI

/// The normal app window: a sticky 212px sidebar and a scrolling content column on the
/// tinted "desk". Onboarding overlays this (see `RootView`).
struct MainWindow: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            Sidebar(model: model)
                .frame(width: 212)

            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.bottom, 150)   // clearance for the floating widget
            }
            .frame(maxWidth: .infinity)
        }
        // Small top inset — just enough to clear the floating traffic lights. The window
        // ignores the (hidden) title-bar safe area so this isn't doubled up.
        .padding(EdgeInsets(top: 16, leading: 26, bottom: 26, trailing: 26))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.desk)
        .ignoresSafeArea(.container, edges: .top)
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
