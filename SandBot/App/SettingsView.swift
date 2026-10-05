//
//  SettingsView.swift
//  SandBot
//
//  Updated with Z-height calibration controls.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("robotHost") private var robotHost: String = "100.95.15.84:8080"
    @ObservedObject private var pitStore = PitBoundaryStore.shared
    @AppStorage("defaultSpeed") private var defaultSpeed: String = "normal"
    @AppStorage("drawingZHeight") private var drawingZHeight: Double = 40.0

    @State private var isCalibrating = false
    @State private var calibrationStatus = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sandBgPrimary.ignoresSafeArea()
                Form {
                    Section("Robot Connection") {
                        HStack {
                            Text("Host")
                                .font(.sandBody)
                                .foregroundColor(.sandTextSecondary)
                            Spacer()
                            TextField("100.x.x.x:8080", text: $robotHost)
                                .font(.sandBody)
                                .foregroundColor(.sandGold)
                                .multilineTextAlignment(.trailing)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                        HStack {
                            Text("Status")
                                .font(.sandBody)
                                .foregroundColor(.sandTextSecondary)
                            Spacer()
                            StatusPill(status: RobotStatusMonitor.shared.connectionStatus)
                        }
                        Button {
                            Task { try? await RobotService.shared.sendMoveCommand(position: "fold") }
                        } label: {
                            Label("Rest Arm (tuck up & unload motors)", systemImage: "powersleep")
                                .font(.sandBody)
                                .foregroundColor(.sandGold)
                        }
                        .buttonStyle(.borderless)
                    }

                    Section("Pen Height Calibration") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Adjust the drawing height until the pen lightly touches the surface. This value is saved automatically.")
                                .font(.sandCaption)
                                .foregroundColor(.sandTextSecondary)

                            HStack {
                                Text("Z Height")
                                    .font(.sandBody)
                                    .foregroundColor(.sandTextSecondary)
                                Spacer()
                                Text(String(format: "%.1f mm", drawingZHeight))
                                    .font(.sandHeader)
                                    .foregroundColor(.sandGold)
                            }

                            HStack(spacing: 16) {
                                Button(action: { adjustZ(by: -1.0) }) {
                                    HStack {
                                        Image(systemName: "arrow.down")
                                        Text("-1")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.sandSurface)
                                    .foregroundColor(.sandGold)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.sandGold.opacity(0.3), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.borderless)

                                Button(action: { adjustZ(by: -0.5) }) {
                                    HStack {
                                        Image(systemName: "arrow.down")
                                        Text("-0.5")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.sandSurface)
                                    .foregroundColor(.sandGold)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.sandGold.opacity(0.3), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.borderless)

                                Button(action: { adjustZ(by: 0.5) }) {
                                    HStack {
                                        Image(systemName: "arrow.up")
                                        Text("+0.5")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.sandSurface)
                                    .foregroundColor(.sandGold)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.sandGold.opacity(0.3), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.borderless)

                                Button(action: { adjustZ(by: 1.0) }) {
                                    HStack {
                                        Image(systemName: "arrow.up")
                                        Text("+1")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.sandSurface)
                                    .foregroundColor(.sandGold)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.sandGold.opacity(0.3), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.borderless)
                            }

                            if !calibrationStatus.isEmpty {
                                Text(calibrationStatus)
                                    .font(.sandCaption)
                                    .foregroundColor(calibrationStatus.contains("Error") ? .sandError : .sandSuccess)
                            }
                        }
                    }

                    Section("Sand Pit") {
                        NavigationLink {
                            PitCalibrationView()
                        } label: {
                            HStack(spacing: 14) {
                                PitBackdrop(boundary: pitStore.boundary)
                                    .frame(width: 64)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Boundary")
                                        .font(.sandBody)
                                        .foregroundColor(.sandTextPrimary)
                                    Text(pitStore.boundary.calibrated ? "Calibrated · rim clearance \(Int(pitStore.boundary.rimClearanceMm ?? 15)) mm" : "Estimated — tap to calibrate")
                                        .font(.sandCaption)
                                        .foregroundColor(pitStore.boundary.calibrated ? .sandTextSecondary : .sandOrange)
                                }
                            }
                        }
                    }

                    Section("Drawing Speed") {
                        Picker("Speed", selection: $defaultSpeed) {
                            Text("Slow").tag("slow")
                            Text("Normal").tag("normal")
                            Text("Fast").tag("fast")
                        }
                        .pickerStyle(.segmented)
                        .tint(Color.sandGold)
                    }

                    Section("App") {
                        HStack {
                            Text("Mock Mode")
                                .font(.sandBody)
                                .foregroundColor(.sandTextSecondary)
                            Spacer()
                            Text(USE_MOCK_ROBOT ? "ON" : "OFF")
                                .font(.sandBody)
                                .foregroundColor(USE_MOCK_ROBOT ? Color.sandOrange : Color.sandSuccess)
                        }
                        HStack {
                            Text("Version")
                                .font(.sandBody)
                                .foregroundColor(.sandTextSecondary)
                            Spacer()
                            Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                                .font(.sandBody)
                                .foregroundColor(.sandTextPrimary)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .task { await syncZFromRobot() }
        }
    }

    private var robotBaseURL: String {
        "http://\(UserDefaults.standard.string(forKey: "robotHost") ?? "100.95.15.84:8080")"
    }

    private struct ZResponse: Decodable {
        let z_height: Double
        let error: String?
    }

    /// The Pi owns the pen height; show its value so the first tap is a 1 mm step.
    private func syncZFromRobot() async {
        guard let url = URL(string: "\(robotBaseURL)/z-height"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let z = try? JSONDecoder().decode(ZResponse.self, from: data) else { return }
        drawingZHeight = z.z_height
    }

    private func adjustZ(by amount: Double) {
        guard !isCalibrating else { return }
        isCalibrating = true


        Task {
            do {
                await syncZFromRobot()  // step from the Pi's real value, not a stale local one
                let target = drawingZHeight + amount
                let url = URL(string: "\(robotBaseURL)/set-z")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.timeoutInterval = 15  // first move may enable motors and home
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: ["z_height": target])
                let (data, _) = try await URLSession.shared.data(for: request)
                let result = try JSONDecoder().decode(ZResponse.self, from: data)
                drawingZHeight = result.z_height
                if let error = result.error {
                    calibrationStatus = "Error: \(error)"
                } else {
                    calibrationStatus = "Z set to \(String(format: "%.1f", result.z_height))mm"
                }
            } catch {
                calibrationStatus = "Error: \(error.localizedDescription)"
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
            isCalibrating = false
        }
    }
}
