import SwiftUI

@main
struct CoralReefWatchApp: App {
    @StateObject private var viewModel = ReefRankingViewModel()
    @StateObject private var notifications = NotificationService.shared

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(viewModel)
                .environmentObject(notifications)
                .task { await viewModel.load(notifications: notifications) }
        }
    }
}

struct RootTabView: View {
    var body: some View {
        TabView {
            ListTabView()
                .tabItem { Image(systemName: "list.number") }

            MapTabView()
                .tabItem { Image(systemName: "map") }

            SettingsView()
                .tabItem { Image(systemName: "gear") }
        }
    }
}
