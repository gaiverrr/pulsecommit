import SwiftUI

struct HealthExportConsentSheet: View {
    let scope: HealthExportConsentScope
    let onAllow: () -> Void
    let onDecline: () -> Void

    private var disclosure: HealthExportDisclosure { HealthExportDisclosure(scope: scope) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("$ pulse export --authorize")
                        .font(.pcCaptionMono)
                        .foregroundStyle(Theme.dim)
                    Text(disclosure.title)
                        .font(.pcTitle)
                        .foregroundStyle(Theme.text)

                    PCCard {
                        VStack(alignment: .leading, spacing: 14) {
                            row("DESTINATION", disclosure.target, monospaced: true)
                            Divider().background(Theme.divider)
                            row("CATEGORIES", disclosure.categorySummary, monospaced: true)
                            Divider().background(Theme.divider)
                            row("FORMATS", disclosure.formats)
                            Divider().background(Theme.divider)
                            row("WHO MAY READ IT", disclosure.readers)
                            Divider().background(Theme.divider)
                            row("RETENTION", disclosure.retention)
                            Divider().background(Theme.divider)
                            row("DISABLE / DELETE", disclosure.deletion)
                        }
                    }

                    Text("Disclosure version \(disclosure.version)")
                        .font(.pcCaptionMono)
                        .foregroundStyle(Theme.dim)

                    Button("Allow this export destination", action: onAllow)
                        .buttonStyle(DSPrimaryButtonStyle())
                    Button("Not now", action: onDecline)
                        .font(.pcBody)
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .buttonStyle(.plain)
                }
                .padding(20)
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func row(_ title: String, _ value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.pcLabel)
                .tracking(1.2)
                .foregroundStyle(Theme.muted)
            Text(value)
                .font(monospaced ? .pcMonoDetail : .pcBodySmall)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
