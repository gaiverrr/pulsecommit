import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class GitHubSubdirEditViewModel {
    var value: String

    private let persist: @MainActor (String) -> Void
    private let onDismiss: @MainActor () -> Void

    static let validationPattern: String = "^[a-zA-Z0-9\\-_/]*$"

    init(
        initial: String,
        persist: @escaping @MainActor (String) -> Void,
        onDismiss: @escaping @MainActor () -> Void
    ) {
        self.value = initial
        self.persist = persist
        self.onDismiss = onDismiss
    }

    static func isValid(_ candidate: String) -> Bool {
        let range = NSRange(candidate.startIndex..<candidate.endIndex, in: candidate)
        guard let regex = try? NSRegularExpression(pattern: validationPattern) else { return false }
        guard regex.firstMatch(in: candidate, options: [], range: range) != nil else { return false }
        let trimmed = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return !trimmed.contains("//")
    }

    var isValid: Bool { Self.isValid(value) }

    func save() {
        guard isValid else { return }
        persist(value)
        onDismiss()
    }

    func cancel() {
        onDismiss()
    }

    static func live(
        initial: String,
        preferences: PreferencesStore,
        onDismiss: @escaping @MainActor () -> Void
    ) -> GitHubSubdirEditViewModel {
        GitHubSubdirEditViewModel(
            initial: initial,
            persist: { value in
                preferences.githubSubdir = value.isEmpty ? nil : value
            },
            onDismiss: onDismiss
        )
    }
}

struct GitHubSubdirEditSheet: View {
    @Bindable var viewModel: GitHubSubdirEditViewModel

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("$ pulse set subdir")
                    .font(.pcMonoDetail)
                    .foregroundStyle(Theme.dim)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 8) {
                    Text("SUBDIR")
                        .font(.pcLabel)
                        .tracking(1.2)
                        .foregroundStyle(Theme.muted)

                    TextField("e.g. health/exports", text: $viewModel.value)
                        .font(.pcMonoDetail)
                        .foregroundStyle(Theme.text)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Theme.elevated)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(viewModel.isValid ? Theme.hairline : Theme.error, lineWidth: 1)
                                )
                        )

                    if !viewModel.isValid {
                        Text("Only letters, digits, '-', '_' and '/' are allowed.")
                            .font(.pcCaptionMono)
                            .foregroundStyle(Theme.error)
                    } else {
                        Text("> empty value writes to repo root")
                            .font(.pcCaptionMono)
                            .foregroundStyle(Theme.faint)
                    }
                }

                Spacer()
            }
            .padding(20)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Edit subdir")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.cancel() }
                        .foregroundStyle(Theme.muted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { viewModel.save() }
                        .foregroundStyle(viewModel.isValid ? Theme.accent : Theme.faint)
                        .disabled(!viewModel.isValid)
                }
            }
        }
    }
}
