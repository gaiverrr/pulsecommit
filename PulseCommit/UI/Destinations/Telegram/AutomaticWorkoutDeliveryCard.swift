import SwiftUI

enum AutomaticWorkoutCardState: Equatable {
    case off
    case on
    case blocked(String)
    case delivered(Date)
    case deliveryUnknown(UUID)

    var statusText: String {
        switch self {
        case .off: return "OFF"
        case .on: return "ON · waiting for a finished workout"
        case .blocked(let reason): return reason
        case .delivered(let date): return "Last delivered \(date.formatted(date: .abbreviated, time: .shortened))"
        case .deliveryUnknown: return "Delivery unknown — check Telegram"
        }
    }
}

struct AutomaticWorkoutDeliveryCard: View {
    let isOn: Bool
    let state: AutomaticWorkoutCardState
    let onToggle: (Bool) -> Void
    let onRetry: (UUID) -> Void
    @State private var pendingRetry: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PCSectionHeader(title: "FINISHED WORKOUTS")
            PCCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Send finished workouts automatically")
                                .font(.pcBodySemibold)
                                .foregroundStyle(Theme.text)
                            Text("One text-only message per saved workout. Best effort; iPhone lock, sync, background time, and network can delay it.")
                                .font(.pcCaption)
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 12)
                        PCToggle(accessibilityLabel: "Send finished workouts automatically", isOn: Binding(
                            get: { isOn },
                            set: onToggle
                        ))
                        .accessibilityIdentifier("automaticWorkout.toggle")
                    }
                    Text(state.statusText)
                        .font(.pcCaptionMono)
                        .foregroundStyle(statusColor)
                        .accessibilityIdentifier("automaticWorkout.status")
                    if case .deliveryUnknown(let id) = state {
                        Button("Retry message") { pendingRetry = id }
                            .buttonStyle(DSPrimaryButtonStyle())
                            .accessibilityHint("May create a duplicate if Telegram received the earlier attempt")
                    }
                    Text("Checks the last 72 hours after your current opt-in time. Deduplication is local to this app installation.")
                        .font(.pcCaption)
                        .foregroundStyle(Theme.dim)
                }
            }
        }
        .confirmationDialog(
            "Telegram may already have the message",
            isPresented: Binding(get: { pendingRetry != nil }, set: { if !$0 { pendingRetry = nil } }),
            titleVisibility: .visible
        ) {
            if let pendingRetry {
                Button("Retry anyway") {
                    self.pendingRetry = nil
                    onRetry(pendingRetry)
                }
            }
            Button("Cancel", role: .cancel) { pendingRetry = nil }
        } message: {
            Text("The earlier result was uncertain. Retrying can create a duplicate workout message.")
        }
    }

    private var statusColor: Color {
        switch state {
        case .on, .delivered: return Theme.success
        case .blocked, .deliveryUnknown: return Theme.warn
        case .off: return Theme.dim
        }
    }
}
