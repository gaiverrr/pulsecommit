import XCTest
@testable import PulseCommit

final class CategoryCatalogTests: XCTestCase {
    func test_sectionTotalsMatchHandoff() {
        XCTAssertEqual(CategoryCatalog.totalCount(in: .activity), 4)
        XCTAssertEqual(CategoryCatalog.totalCount(in: .heart), 4)
        XCTAssertEqual(CategoryCatalog.totalCount(in: .sleepBodyMind), 5)
        XCTAssertEqual(CategoryCatalog.totalCount(in: .workouts), 2)
        XCTAssertEqual(CategoryCatalog.totalCount(in: .nutrition), 2)
        XCTAssertEqual(CategoryCatalog.totalCount(in: .lab), 2)
    }

    func test_enabledCount_reflectsEnabledIdsForRegistryAndBundledRows() {
        let enabled: Set<String> = ["steps", "active_energy", "workouts"]
        XCTAssertEqual(CategoryCatalog.enabledCount(in: .activity, enabledIds: enabled), 2)
        XCTAssertEqual(CategoryCatalog.enabledCount(in: .workouts, enabledIds: enabled), 2)
    }

    func test_labSection_alwaysReportsZeroEnabled() {
        let enabled: Set<String> = ["blood_oxygen", "respiratory_rate", "mindful_minutes"]
        XCTAssertEqual(CategoryCatalog.enabledCount(in: .lab, enabledIds: enabled), 0)
    }

    func test_nutritionSection_excludesPlaceholderHydration() {
        let enabled: Set<String> = ["nutrition", "hydration"]
        XCTAssertEqual(CategoryCatalog.enabledCount(in: .nutrition, enabledIds: enabled), 1)
    }

    func test_allDefaultMVPCategoryIdsAppearInCatalog() {
        let catalogIds = Set(CategoryCatalog.sections.flatMap { $0.1 }.compactMap { spec -> String? in
            if case .registry(let id) = spec.kind { return id }
            return nil
        })
        XCTAssertEqual(PreferencesStore.defaultCategoryIds.subtracting(catalogIds), [])
    }
}
