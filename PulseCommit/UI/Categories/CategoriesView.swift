import SwiftUI
import HealthKit

struct CategoriesView: View {
    @EnvironmentObject var container: AppContainer
    @State private var enabledIds: Set<String> = []
    @State private var authorizationError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                ForEach(CategoryCatalog.sections, id: \.0) { section, rows in
                    sectionBlock(section: section, rows: rows)
                }
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .onAppear { enabledIds = container.preferences.enabledCategoryIds }
        .alert("Health access", isPresented: Binding(
            get: { authorizationError != nil }, set: { if !$0 { authorizationError = nil } }
        )) {
            Button("OK") { authorizationError = nil }
        } message: {
            Text(authorizationError ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("$ pulse categories --list")
                .font(.pcCaptionMono)
                .foregroundStyle(Theme.dim)
            Text("Categories")
                .font(.pcLargeTitle)
                .foregroundStyle(Theme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionBlock(section: CategorySectionKind, rows: [CategoryRowSpec]) -> some View {
        let enabled = CategoryCatalog.enabledCount(in: section, enabledIds: enabledIds)
        let total = CategoryCatalog.totalCount(in: section)
        return VStack(spacing: 8) {
            PCSectionHeader(title: section.title, hint: "\(enabled)/\(total)")
            PCCard(padding: 8) {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        CategoryRowView(
                            spec: row,
                            isOn: isOn(row),
                            isLocked: isLocked(row),
                            liveValue: nil,
                            onToggle: { newValue in toggle(row, on: newValue) }
                        )
                        .padding(.horizontal, 8)
                        if index < rows.count - 1 {
                            Divider().background(Theme.divider)
                        }
                    }
                }
            }
        }
    }

    private func isOn(_ row: CategoryRowSpec) -> Bool {
        switch row.kind {
        case .registry(let id): return enabledIds.contains(id)
        case .bundledWith(let id): return enabledIds.contains(id)
        case .placeholder, .lab: return false
        }
    }

    private func isLocked(_ row: CategoryRowSpec) -> Bool {
        switch row.kind {
        case .registry: return false
        case .bundledWith, .placeholder, .lab: return true
        }
    }

    private func toggle(_ row: CategoryRowSpec, on newValue: Bool) {
        guard case .registry(let id) = row.kind else { return }
        if newValue && ["respiratory_rate", "wrist_temperature"].contains(id) {
            let readTypes: Set<HKObjectType> = id == "wrist_temperature"
                ? [HKQuantityType.quantityType(forIdentifier: .appleSleepingWristTemperature)!]
                : [HKQuantityType.quantityType(forIdentifier: .respiratoryRate)!,
                   HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!]
            Task { @MainActor in
                do {
                    try await container.healthStore.requestAuthorization(toShare: nil, read: readTypes)
                    enabledIds.insert(id)
                    container.preferences.enabledCategoryIds = enabledIds
                } catch {
                    authorizationError = error.localizedDescription
                }
            }
            return
        }
        if newValue {
            enabledIds.insert(id)
        } else {
            enabledIds.remove(id)
        }
        container.preferences.enabledCategoryIds = enabledIds
    }
}
