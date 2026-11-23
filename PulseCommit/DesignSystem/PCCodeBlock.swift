import SwiftUI

struct PCCodeBlock: View {
    let content: String
    var foreground: Color = Theme.text
    var padding: CGFloat = 14
    var cornerRadius: CGFloat = 12

    var body: some View {
        Text(content)
            .font(.pcMonoDetail)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.black)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }
}
