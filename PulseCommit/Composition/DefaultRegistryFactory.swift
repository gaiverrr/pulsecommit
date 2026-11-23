import Foundation
import HealthCore

public enum DefaultRegistryFactory {
    public static func make(store: any HealthStoreAuthorizing, timezone: TimeZone = .current, zoneConfiguration: HeartRateZoneConfiguration? = nil) -> CategoryRegistry {
        CategoryRegistry(categories: [
            StepsCategory(store: store),
            DistanceWalkingRunningCategory(store: store),
            HeartRateCategory(store: store),
            RestingHeartRateCategory(store: store),
            HRVCategory(store: store),
            VO2MaxCategory(store: store),
            ActiveEnergyCategory(store: store),
            ActivityRingsCategory(store: store),
            SleepCategory(store: store),
            RespiratoryRateCategory(store: store),
            WristTemperatureCategory(store: store, timezone: timezone),
            WorkoutsCategory(store: store, zoneConfiguration: zoneConfiguration),
            BodyMassCategory(store: store),
            StateOfMindCategory(store: store),
            NutritionCategory(store: store)
        ])
    }
}
