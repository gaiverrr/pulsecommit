import SwiftUI

struct GitHubDisconnectedView: View {
    let onConnect: () -> Void

    static let rationaleItems: [String] = [
        "Contents: read & write",
        "Metadata: read",
        "Only the repository you pick",
        "Nothing else"
    ]

    static let footnoteLines: [String] = [
        "> Tokens stored only in Keychain",
        "> Never sent to any backend"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("$ pulse connect github")
                    .font(.pcMonoDetail)
                    .foregroundStyle(Theme.dim)
                    .padding(.top, 8)

                PCCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("GitHub will be asked for:")
                            .font(.pcBodySemibold)
                            .foregroundStyle(Theme.text)
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Self.rationaleItems, id: \.self) { item in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("•")
                                        .font(.pcBody)
                                        .foregroundStyle(Theme.dim)
                                    Text(item)
                                        .font(.pcBody)
                                        .foregroundStyle(Theme.muted)
                                }
                            }
                        }
                    }
                }

                Button(action: onConnect) {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.fill")
                        Text("Connect GitHub")
                    }
                }
                .buttonStyle(DSPrimaryButtonStyle(glows: true))

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Self.footnoteLines, id: \.self) { line in
                        Text(line)
                            .font(.pcCaptionMono)
                            .foregroundStyle(Theme.faint)
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}
