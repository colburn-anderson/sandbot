//
//  LiveFeedView.swift
//  SandBot
//
//  Created by Anderson Colburn on 4/16/26.
//

import SwiftUI

struct LiveFeedView: View {
    @EnvironmentObject var statusMonitor: RobotStatusMonitor
    @State private var viewMode: FeedMode = .tip

    enum FeedMode { case tip, overview }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {

                    // Feed area — MJPEG from camera_stream.py on the Pi
                    LiveCameraView()
                        .frame(maxWidth: .infinity)

                    // Controls
                    VStack(spacing: 16) {
                        Picker("View Mode", selection: $viewMode) {
                            Text("Tip View").tag(FeedMode.tip)
                            Text("Overview").tag(FeedMode.overview)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)

                        PrimaryButton(
                            title: "Take Snapshot",
                            action: { },
                            isDisabled: statusMonitor.connectionStatus != .online,
                            style: .secondary
                        )
                        .padding(.horizontal)

                        Text("Camera feed streams over Tailscale when your robot is online.")
                            .font(.sandCaption)
                            .foregroundColor(.sandTextSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.vertical)
                    .background(Color.sandBgPrimary)

                    Spacer()
                }
            }
            .navigationTitle("Live Feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    StatusPill(status: statusMonitor.connectionStatus)
                }
            }
        }
    }
}
