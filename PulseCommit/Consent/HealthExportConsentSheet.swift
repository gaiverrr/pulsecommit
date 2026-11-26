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

                    if !disclosure.webhookNotice.isEmpty {
                        webhookNotice
                    }

                    PCCard {
                        VStack(alignment: .leading, spacing: 14) {
                            row("DESTINATION", disclosure.target, monospaced: true)
                            Divider().background(Theme.divider)
                            row("CATEGORIES", disclosure.categorySummary, monospaced: true)
                            Divider().background(Theme.divider)
                            row("FORMATS", disclosure.formats)
                            if disclosure.webhookNotice.isEmpty {
                                Divider().background(Theme.divider)
                                row("WHO MAY READ IT", disclosure.readers)
                                Divider().background(Theme.divider)
                                row("RETENTION", disclosure.retention)
                            }
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

    private var webhookNotice: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(disclosure.webhookNotice.enumerated()), id: \.offset) { index, paragraph in
                paragraphText(paragraph, emphasizing: index == 0 ? disclosure.target : nil)
                    .font(.pcBodySmall)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("consent.webhook.notice")
    }

    private func paragraphText(_ paragraph: String, emphasizing host: String?) -> Text {
        guard let host, let range = paragraph.range(of: host) else { return Text(verbatim: paragraph) }
        let before = Text(verbatim: String(paragraph[..<range.lowerBound]))
        let emphasized = Text(verbatim: host).font(.pcMonoDetail.weight(.semibold))
        let after = Text(verbatim: String(paragraph[range.upperBound...]))
        return Text("\(before)\(emphasized)\(after)")
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
