import SwiftUI

struct PCSectionHeader: View {
    let title: String
    var hint: String? = nil

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.pcLabel)
                .tracking(1.5)
                .foregroundStyle(Theme.dim)
            Spacer()
            if let hint {
                Text(hint)
                    .font(.pcLabel)
                    .tracking(1.5)
                    .foregroundStyle(Theme.muted)
            }
        }
    }
}
