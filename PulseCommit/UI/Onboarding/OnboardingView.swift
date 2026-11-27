import SwiftUI

struct OnboardingView: View {
    let healthStore: any HealthStoreAuthorizing

    @AppStorage("onboarding_completed") private var onboardingCompleted: Bool = false
    @State private var page: Int = 0

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            TabView(selection: $page) {
                welcomePage
                    .tag(0)
                HealthRationaleView {
                    withAnimation { page = 2 }
                }
                .tag(1)
                HealthAuthorizationView(healthStore: healthStore) {
                    onboardingCompleted = true
                }
                .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
    }

    private var welcomePage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 24)

            Text("$ pulse commit --version")
                .font(.pcCaptionMono)
                .foregroundStyle(Theme.dim)

            Spacer().frame(height: 16)

            Text("Pulse Commit")
                .font(.pcLargeTitle)
                .foregroundStyle(Theme.text)

            Spacer().frame(height: 8)

            Text("v1.0")
                .font(.pcMonoDetail)
                .foregroundStyle(Theme.accent)

            Spacer().frame(height: 24)

            Text("Export Apple Health to your Telegram chat, GitHub repo or webhook. Your data stays yours.")
                .font(.pcBodyLarge)
                .foregroundStyle(Theme.muted)

            Spacer().frame(height: 32)

            PCCard(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    bulletRow(label: "Atomic", value: "summary.json + samples + GPX")
                    bulletRow(label: "Yours", value: "your repo, your chat, your data")
                    bulletRow(label: "Private", value: "no backend, no analytics")
                }
            }

            Spacer()

            HStack(spacing: 6) {
                Text("Swipe to continue")
                    .font(.pcCaptionMono)
                    .foregroundStyle(Theme.dim)
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, 48)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg)
    }

    private func bulletRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label.uppercased())
                .font(.pcLabel)
                .foregroundStyle(Theme.accent)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.pcBody)
                .foregroundStyle(Theme.text)
        }
    }
}
