import SwiftUI
import HealthKit

struct HealthAuthorizationView: View {
    let healthStore: any HealthStoreAuthorizing
    let onCompleted: () -> Void

    @State private var phase: Phase = .idle
    @State private var errorMessage: String?

    enum Phase: Equatable {
        case idle
        case requesting
        case requestCompleted
        case failed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 24)

            Text("$ pulse commit --grant-access")
                .font(.pcCaptionMono)
                .foregroundStyle(Theme.dim)

            Spacer().frame(height: 16)

            Text("Grant Health\naccess")
                .font(.pcLargeTitle)
                .foregroundStyle(Theme.text)

            Spacer().frame(height: 12)

            Text("Pulse Commit reads from Apple Health on-device only. Tokens stay in the Keychain. Nothing is sent to us.")
                .font(.pcBodyLarge)
                .foregroundStyle(Theme.muted)

            Spacer().frame(height: 32)

            PCCard(padding: 0) {
                VStack(spacing: 0) {
                    permissionRow(icon: "figure.walk", label: "Activity", hint: "steps · distance · energy")
                    Divider().background(Theme.divider)
                    permissionRow(icon: "heart.fill", label: "Heart", hint: "rate · resting · HRV · VO2max")
                    Divider().background(Theme.divider)
                    permissionRow(icon: "bed.double.fill", label: "Sleep · Body · Mind", hint: "sleep · mass · state-of-mind")
                    Divider().background(Theme.divider)
                    permissionRow(icon: "figure.run", label: "Workouts", hint: "sessions · routes (GPX)")
                    Divider().background(Theme.divider)
                    permissionRow(icon: "fork.knife", label: "Nutrition", hint: "dietary energy")
                }
            }

            Spacer()

            if let errorMessage {
                Text("> \(errorMessage)")
                    .font(.pcCaptionMono)
                    .foregroundStyle(Theme.error)
                    .padding(.bottom, 12)
            }

            if phase == .requestCompleted {
                Text("Permission request completed. Apple Health does not tell apps which read categories you allowed. You can review them in the Health app: profile → Privacy → Apps.")
                    .font(.pcCaption)
                    .foregroundStyle(Theme.muted)
                    .padding(.bottom, 12)
            }

            Button(action: request) {
                Text(buttonLabel)
            }
            .buttonStyle(DSPrimaryButtonStyle(glows: phase == .idle))
            .disabled(phase == .requesting)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg.ignoresSafeArea())
    }

    private var buttonLabel: String {
        switch phase {
        case .idle: return "Enable Health Access"
        case .requesting: return "Requesting…"
        case .requestCompleted: return "Continue"
        case .failed: return "Try Again"
        }
    }

    private func permissionRow(icon: String, label: String, hint: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.accentSoft)
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.pcBody)
                    .foregroundStyle(Theme.text)
                Text(hint)
                    .font(.pcCaptionMono)
                    .foregroundStyle(Theme.dim)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func request() {
        if phase == .requestCompleted {
            onCompleted()
            return
        }
        phase = .requesting
        errorMessage = nil
        Task {
            do {
                try await healthStore.requestAuthorization(
                    toShare: nil,
                    read: HealthAuthorizationView.readTypes()
                )
                await MainActor.run {
                    phase = .requestCompleted
                }
            } catch {
                await MainActor.run {
                    phase = .failed
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    static func readTypes() -> Set<HKObjectType> {
        var types: Set<HKObjectType> = []

        let quantityIdentifiers: [HKQuantityTypeIdentifier] = [
            .stepCount,
            .distanceWalkingRunning,
            .heartRate,
            .restingHeartRate,
            .heartRateVariabilitySDNN,
            .respiratoryRate,
            .appleSleepingWristTemperature,
            .vo2Max,
            .activeEnergyBurned,
            .appleExerciseTime,
            .appleStandTime,
            .bodyMass,
            .dietaryEnergyConsumed,
            .dietaryProtein,
            .dietaryCarbohydrates,
            .dietaryFatTotal,
            .dietaryFiber,
            .dietarySugar,
            .dietaryWater,
            .dietaryCaffeine
        ]
        for id in quantityIdentifiers {
            if let t = HKQuantityType.quantityType(forIdentifier: id) {
                types.insert(t)
            }
        }

        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }

        types.insert(HKObjectType.workoutType())
        types.insert(HKSeriesType.workoutRoute())

        if #available(iOS 18.0, *) {
            types.insert(HKObjectType.stateOfMindType())
        }

        return types
    }
}
