import SwiftUI

struct PlainSecretField: View {
    let title: String
    let placeholder: String
    @Binding var value: String
    var valueColor: Color = Theme.text
    var monospaced: Bool = true
    var autocapitalization: TextInputAutocapitalization = .never

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.pcLabel)
                .tracking(1.5)
                .foregroundStyle(Theme.dim)
            TextField(placeholder, text: $value)
                .font(monospaced ? .pcMonoDetail : .pcBody)
                .foregroundStyle(value.isEmpty ? Theme.faint : valueColor)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled()
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.elevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 1)
                )
        }
    }
}
