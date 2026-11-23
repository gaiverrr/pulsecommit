import XCTest
import HealthKit
@testable import PulseCommit

final class WorkoutActiveIntervalsTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 0)
    private func event(_ type: HKWorkoutEventType, _ seconds: Double) -> HKWorkoutEvent {
        HKWorkoutEvent(type: type, dateInterval: DateInterval(start: start.addingTimeInterval(seconds), duration: 0), metadata: nil)
    }
    func test_manualAndMotionPausesStayExcludedUntilBothResume() {
        let intervals = workoutActiveIntervals(start: start, end: start.addingTimeInterval(60), events: [
            event(.resume, 40), event(.pause, 20), event(.motionPaused, 30), event(.motionResumed, 50)
        ])
        XCTAssertEqual(intervals, [DateInterval(start: start, duration: 20), DateInterval(start: start.addingTimeInterval(50), duration: 10)])
    }
    func test_pauseWithoutResumeExcludesRemainingTime() {
        let intervals = workoutActiveIntervals(start: start, end: start.addingTimeInterval(60), events: [event(.pause, 10)])
        XCTAssertEqual(intervals, [DateInterval(start: start, duration: 10)])
    }
    func test_noEventsUsesWholeWorkout() {
        XCTAssertEqual(workoutActiveIntervals(start: start, end: start.addingTimeInterval(60), events: []),
                       [DateInterval(start: start, duration: 60)])
    }
}
