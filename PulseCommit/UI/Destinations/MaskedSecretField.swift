import SwiftUI

struct MaskedSecretField: View {
    let title: String
    let placeholder: String
    @Binding var value: String
    var leadingIcon: String? = "lock.fill"

    @State private var isEditing: Bool = false
    @State private var draft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased())
                    .font(.pcLabel)
                    .tracking(1.5)
                    .foregroundStyle(Theme.dim)
                Spacer()
                Button(isEditing ? "Cancel" : (value.isEmpty ? "Add" : "Edit")) {
                    if isEditing {
                        isEditing = false
                    } else {
                        draft = ""
                        isEditing = true
                    }
                }
                .font(.pcCaption)
                .foregroundStyle(Theme.accent)
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                if let leadingIcon {
                    Image(systemName: leadingIcon)
                        .foregroundStyle(Theme.dim)
                        .font(.system(size: 13))
                }
                if isEditing {
                    SecureField(placeholder, text: $draft)
                        .font(.pcMonoDetail)
                        .foregroundStyle(Theme.text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save") {
                        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            value = trimmed
                        }
                        isEditing = false
                    }
                    .font(.pcCaption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .buttonStyle(.plain)
                } else {
                    Text(maskedDisplay)
                        .font(.pcMonoDetail)
                        .foregroundStyle(value.isEmpty ? Theme.faint : Theme.text)
                    Spacer(minLength: 0)
                }
            }
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

    private var maskedDisplay: String {
        if value.isEmpty { return placeholder }
        let prefix = inferredPrefix(for: value)
        let revealable = value.dropFirst(prefix.count)
        guard revealable.count > 8 else {
            return "\(prefix)•••••••••••••••••••"
        }
        return "\(prefix)•••••••••••••••\(revealable.suffix(4))"
    }

    private func inferredPrefix(for token: String) -> String {
        if token.hasPrefix("ghp_") { return "ghp_" }
        if token.hasPrefix("github_pat_") { return "github_pat_" }
        if let colon = token.firstIndex(of: ":"), token.distance(from: token.startIndex, to: colon) <= 10 {
            return String(token[..<colon]) + ":"
        }
        return ""
    }
}
