import XCTest
import SwiftUI
@testable import PulseCommit

@MainActor
final class HealthRationaleViewTests: XCTestCase {
    func test_categories_includeCoreHealthKitTypes() {
        let names = HealthRationaleView.categories
        XCTAssertTrue(names.contains("Steps"))
        XCTAssertTrue(names.contains("Distance"))
        XCTAssertTrue(names.contains("Active Energy"))
        XCTAssertTrue(names.contains("Activity Rings"))
        XCTAssertTrue(names.contains("Heart Rate"))
        XCTAssertTrue(names.contains("Resting HR"))
        XCTAssertTrue(names.contains("HRV"))
        XCTAssertTrue(names.contains("VO₂ Max"))
        XCTAssertTrue(names.contains("Sleep"))
        XCTAssertTrue(names.contains("Body Mass"))
        XCTAssertTrue(names.contains("Workouts"))
        XCTAssertTrue(names.contains("Nutrition"))
    }

    func test_categories_listWorkoutRoutes() {
        // Authorization requests HKSeriesType.workoutRoute(); the rationale
        // screen must disclose it so the read-set matches what users see.
        let names = HealthRationaleView.categories
        XCTAssertTrue(names.contains("Workout Routes"))
    }

    func test_categories_stateOfMindMatchesIOSAvailability() {
        let names = HealthRationaleView.categories
        if #available(iOS 18.0, *) {
            XCTAssertTrue(names.contains("State of Mind"),
                          "State of Mind should be listed on iOS 18+ where HKObjectType.stateOfMindType() is requested.")
        } else {
            XCTAssertFalse(names.contains("State of Mind"),
                           "State of Mind must not appear pre-iOS 18 — the type is unavailable and HealthAuthorizationView.readTypes() skips it.")
        }
    }

    // Exercises both branches independently of the test runner's OS so the
    // iOS-gated list cannot silently regress on either side.
    func test_categories_stateOfMindAvailable_listsStateOfMind() {
        let names = HealthRationaleView.categories(stateOfMindAvailable: true)
        XCTAssertTrue(names.contains("State of Mind"))
        // Must remain ordered before the trailing Workouts/Nutrition rows.
        let stateOfMindIdx = names.firstIndex(of: "State of Mind")
        let workoutsIdx = names.firstIndex(of: "Workouts")
        XCTAssertNotNil(stateOfMindIdx)
        XCTAssertNotNil(workoutsIdx)
        XCTAssertLessThan(stateOfMindIdx!, workoutsIdx!)
    }

    func test_categories_stateOfMindUnavailable_omitsStateOfMind() {
        let names = HealthRationaleView.categories(stateOfMindAvailable: false)
        XCTAssertFalse(names.contains("State of Mind"))
        XCTAssertTrue(names.contains("Workouts"))
        XCTAssertTrue(names.contains("Nutrition"))
    }

    func test_categories_doNotListRawDietarySubtypes() {
        // Dietary subtypes are folded into the single "Nutrition" disclosure
        // entry. Listing them individually would mislead users about prompts.
        let names = HealthRationaleView.categories
        for forbidden in ["Dietary Energy", "Protein", "Carbohydrates", "Caffeine", "Water"] {
            XCTAssertFalse(names.contains(forbidden),
                           "\(forbidden) should be folded into Nutrition, not listed separately.")
        }
    }

func test_tipLine_mentionsOnDeviceUntilDestinationConfigured() {
        let tip = HealthRationaleView.tipLine
        XCTAssertTrue(tip.localizedCaseInsensitiveContains("on device"))
        XCTAssertTrue(tip.localizedCaseInsensitiveContains("destination"))
    }

    func test_view_canBeInstantiated() {
        var called = 0
        _ = HealthRationaleView(onContinue: { called += 1 })
        XCTAssertEqual(called, 0)
    }

    func test_onContinue_isStoredAndInvoked() {
        var called = 0
        let view = HealthRationaleView(onContinue: { called += 1 })
        let mirror = Mirror(reflecting: view)
        let onContinue = mirror.children.first(where: { $0.label == "onContinue" })?.value as? () -> Void
        XCTAssertNotNil(onContinue)
        onContinue?()
        XCTAssertEqual(called, 1)
    }
}
