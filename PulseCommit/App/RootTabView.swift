import SwiftUI
import UIKit

struct RootTabView: View {
    @EnvironmentObject var container: AppContainer
    @State private var selectedTab: Tab = .home
    @State private var destinationsPath: [DestinationsRoute] = []

    enum Tab: Hashable {
        case home, categories, destinations, history, settings
    }

    enum DestinationsRoute: Hashable {
        case github, telegram
    }

    init() {
        Self.configureTabBarAppearance()
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeContainerView(selectedTab: $selectedTab, destinationsPath: $destinationsPath)
                .tabItem {
                    Label {
                        Text("Home")
                    } icon: {
                        Image(systemName: "house.fill")
                    }
                }
                .tag(Tab.home)

            CategoriesView()
                .tabItem {
                    Label {
                        Text("Categories")
                    } icon: {
                        Image(systemName: "list.bullet")
                    }
                }
                .tag(Tab.categories)

            DestinationsView(path: $destinationsPath, onBackToHome: {
                destinationsPath = []
                selectedTab = .home
            })
                .tabItem {
                    Label {
                        Text("Destinations")
                    } icon: {
                        Image(systemName: "powerplug.fill")
                    }
                }
                .tag(Tab.destinations)

            HistoryContainerView()
                .tabItem {
                    Label {
                        Text("History")
                    } icon: {
                        Image(systemName: "clock.fill")
                    }
                }
                .tag(Tab.history)

            SettingsView(onBackToHome: { selectedTab = .home })
                .tabItem {
                    Label {
                        Text("Settings")
                    } icon: {
                        Image(systemName: "gearshape.fill")
                    }
                }
                .tag(Tab.settings)
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }

    private static func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        appearance.backgroundColor = UIColor(red: 0x0a / 255, green: 0x0a / 255, blue: 0x0a / 255, alpha: 0.75)
        appearance.shadowColor = UIColor.white.withAlphaComponent(0.10)

        let accent = UIColor(red: 0xA4 / 255, green: 0xF0 / 255, blue: 0x3A / 255, alpha: 1)
        let dim = UIColor(red: 0x73 / 255, green: 0x73 / 255, blue: 0x73 / 255, alpha: 1)

        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold)
        ]

        let normal = appearance.stackedLayoutAppearance.normal
        normal.iconColor = dim
        normal.titleTextAttributes = labelAttrs.merging([.foregroundColor: dim]) { $1 }

        let selected = appearance.stackedLayoutAppearance.selected
        selected.iconColor = accent
        selected.titleTextAttributes = labelAttrs.merging([.foregroundColor: accent]) { $1 }

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}
