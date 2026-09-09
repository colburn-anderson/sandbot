//
//  SettingsView.swift
//  SandBot
//
//  Updated with Z-height calibration controls.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("robotHost") private var robotHost: String = "100.95.15.84:8080"
    @AppStorage("surfaceWidthMm") private var surfaceWidth: Double = 500
    @AppStorage("surfaceHeightMm") private var surfaceHeight: Double = 500
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

                    Section("Drawing Surface") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Width")
                                    .font(.sandBody)
                                    .foregroundColor(.sandTextSecondary)
                                Spacer()
                                Text("\(Int(surfaceWidth)) mm")
                                    .font(.sandBody)
                                    .foregroundColor(.sandTextPrimary)
                            }
                            Slider(value: $surfaceWidth, in: 100...1000, step: 50)
                                .tint(Color.sandGold)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Height")
                                    .font(.sandBody)
                                    .foregroundColor(.sandTextSecondary)
                                Spacer()
                                Text("\(Int(surfaceHeight)) mm")
                                    .font(.sandBody)
                                    .foregroundColor(.sandTextPrimary)
                            }
                            Slider(value: $surfaceHeight, in: 100...1000, step: 50)
                                .tint(Color.sandGold)
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
        }
    }

    private func adjustZ(by amount: Double) {
        guard !isCalibrating else { return }
        isCalibrating = true

        let newZ = drawingZHeight + amount
        drawingZHeight = newZ

        Task {
            do {
                let host = UserDefaults.standard.string(forKey: "robotHost") ?? "100.95.15.84:8080"
                let url = URL(string: "http://\(host)/set-z")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.timeoutInterval = 5
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let payload: [String: Double] = ["z_height": newZ]
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)
                let (_, _) = try await URLSession.shared.data(for: request)
                calibrationStatus = "Z set to \(String(format: "%.1f", newZ))mm"
            } catch {
                calibrationStatus = "Error: \(error.localizedDescription)"
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
            isCalibrating = false
        }
    }
}
