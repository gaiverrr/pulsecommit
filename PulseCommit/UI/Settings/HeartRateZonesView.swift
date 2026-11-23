import SwiftUI
import HealthCore

struct HeartRateZonesView: View {
    @EnvironmentObject var container: AppContainer
    @State private var bounds = Array(repeating: "", count: 4)
    @State private var saved = false
    @FocusState private var focusedField: Int?

    private var configuration: HeartRateZoneConfiguration? {
        let values = bounds.compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        return HeartRateZoneConfiguration(lowerBoundsBPM: values)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Enter the lower limit for zones 2–5. Zone 1 covers readings below the first limit. Use your own boundaries; PulseCommit cannot read Apple Watch's zone settings.")
                    .font(.pcBody).foregroundStyle(Theme.muted)
                PCCard {
                    VStack(spacing: 16) {
                        ForEach(0..<4) { index in
                            HStack {
                                Text("Zone \(index + 2) starts at").font(.pcBody)
                                Spacer()
                                TextField("—", text: $bounds[index])
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .font(.pcMonoDetail)
                                    .frame(width: 80)
                                    .focused($focusedField, equals: index)
                                    .accessibilityLabel("Zone \(index + 2) lower limit in bpm")
                                Text("bpm").font(.pcCaptionMono).foregroundStyle(Theme.dim)
                            }
                        }
                    }.foregroundStyle(Theme.text)
                }
                if configuration == nil && bounds.contains(where: { !$0.isEmpty }) {
                    Text("Enter four increasing whole numbers between 1 and 300 bpm.")
                        .font(.pcCaption).foregroundStyle(Theme.warn)
                }
                Text("Time in each zone is an estimate. Each recorded heart rate is used for up to 30 seconds; longer gaps and workout pauses are excluded. Reports show how much active time has HR coverage.")
                    .font(.pcBody).foregroundStyle(Theme.muted)
                Button("Save zones") {
                    guard let configuration else { return }
                    container.preferences.heartRateZoneConfiguration = configuration
                    focusedField = nil
                    saved = true
                }
                .buttonStyle(DSPrimaryButtonStyle())
                .disabled(configuration == nil)
                .opacity(configuration == nil ? 0.5 : 1)
                Button("Turn off zone estimates") {
                    container.preferences.heartRateZoneConfiguration = nil
                    bounds = Array(repeating: "", count: 4)
                    focusedField = nil
                }
                .foregroundStyle(Theme.muted)
                if saved {
                    Text("Saved. These boundaries apply to your next export.")
                        .font(.pcCaption).foregroundStyle(Theme.success)
                }
            }.padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Heart Rate Zones")
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
        .onAppear {
            if let configuration = container.preferences.heartRateZoneConfiguration {
                bounds = configuration.lowerBoundsBPM.map(String.init)
            }
        }
        .onChange(of: bounds) { _, _ in saved = false }
    }
}
