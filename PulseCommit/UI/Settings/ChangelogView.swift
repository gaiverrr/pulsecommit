import SwiftUI

struct ChangelogEntry: Identifiable, Equatable {
    let version: String
    let items: [String]

    var id: String { version }
}

struct ChangelogView: View {
    static let entries: [ChangelogEntry] = [
        ChangelogEntry(version: "1.0.1", items: [
            "Settings → About links open the website, source code, email and changelog.",
            "Workout reports list one split series. Apple Watch records kilometer and mile splits in parallel; Telegram now shows the main series, labeled km or mile splits. All splits stay in the JSON.",
            "After a few successful exports, the app may ask for an App Store rating. iOS limits how often this appears."
        ]),
        ChangelogEntry(version: "1.0", items: [
            "First release. Export Apple Health to your own GitHub repository (summary.json, summary.md, samples, workouts, GPX routes) or Telegram chat (summary plus ZIP).",
            "Today, Yesterday, 7-day and 30-day exports from Home; Export Last Day, Export Health Data and Backfill Range in Shortcuts.",
            "Optional text-only Telegram message for each finished workout.",
            "Free: no export limit, in-app purchase or subscription."
        ])
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("$ git log --oneline --tags")
                    .font(.pcCaptionMono)
                    .foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Self.entries) { entry in
                    PCCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("v\(entry.version)")
                                .font(.pcMonoDetail)
                                .foregroundStyle(Theme.accent)
                            ForEach(entry.items, id: \.self) { item in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("›")
                                        .font(.pcCaptionMono)
                                        .foregroundStyle(Theme.dim)
                                    Text(item)
                                        .font(.pcBodySmall)
                                        .foregroundStyle(Theme.text)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Link(destination: AboutLinks.commitHistory) {
                    Text("Full history on GitHub")
                        .font(.pcBodySmall)
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Changelog")
        .navigationBarTitleDisplayMode(.large)
    }
}

enum AboutLinks {
    static let website = URL(string: "https://pulsecommit.app")!
    static let source = URL(string: "https://github.com/gaiverrr/pulsecommit")!
    static let commitHistory = URL(string: "https://github.com/gaiverrr/pulsecommit/commits/main")!
    static let contact = URL(string: "mailto:hi@pulsecommit.app")!
}
