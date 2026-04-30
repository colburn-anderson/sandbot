//
//  SettingsView.swift
//  SandBot
//
//  Created by Anderson Colburn on 4/16/26.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("robotHost") private var robotHost: String = "sandbot.local"
    @AppStorage("surfaceWidthMm") private var surfaceWidth: Double = 500
    @AppStorage("surfaceHeightMm") private var surfaceHeight: Double = 500
    @AppStorage("defaultSpeed") private var defaultSpeed: String = "normal"

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
                            TextField("100.x.x.x:5000", text: $robotHost)
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
}
