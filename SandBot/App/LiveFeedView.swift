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

                    // Feed area
                    ZStack {
                        Rectangle()
                            .fill(Color(hex: "#0A0A0A"))

                        // Grid overlay
                        Canvas { context, size in
                            let cols = 3, rows = 3
                            for i in 1..<cols {
                                let x = size.width / CGFloat(cols) * CGFloat(i)
                                var path = Path()
                                path.move(to: CGPoint(x: x, y: 0))
                                path.addLine(to: CGPoint(x: x, y: size.height))
                                context.stroke(path, with: .color(.white.opacity(0.06)), lineWidth: 1)
                            }
                            for i in 1..<rows {
                                let y = size.height / CGFloat(rows) * CGFloat(i)
                                var path = Path()
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: size.width, y: y))
                                context.stroke(path, with: .color(.white.opacity(0.06)), lineWidth: 1)
                            }
                        }

                        // Center crosshair
                        Canvas { context, size in
                            let cx = size.width / 2
                            let cy = size.height / 2
                            let len: CGFloat = 20
                            let gap: CGFloat = 6

                            var p1 = Path()
                            p1.move(to: CGPoint(x: cx - len - gap, y: cy))
                            p1.addLine(to: CGPoint(x: cx - gap, y: cy))
                            context.stroke(p1, with: .color(.yellow.opacity(0.6)), lineWidth: 1)

                            var p2 = Path()
                            p2.move(to: CGPoint(x: cx + gap, y: cy))
                            p2.addLine(to: CGPoint(x: cx + len + gap, y: cy))
                            context.stroke(p2, with: .color(.yellow.opacity(0.6)), lineWidth: 1)

                            var p3 = Path()
                            p3.move(to: CGPoint(x: cx, y: cy - len - gap))
                            p3.addLine(to: CGPoint(x: cx, y: cy - gap))
                            context.stroke(p3, with: .color(.yellow.opacity(0.6)), lineWidth: 1)

                            var p4 = Path()
                            p4.move(to: CGPoint(x: cx, y: cy + gap))
                            p4.addLine(to: CGPoint(x: cx, y: cy + len + gap))
                            context.stroke(p4, with: .color(.yellow.opacity(0.6)), lineWidth: 1)
                        }

                        // Corner brackets
                        GeometryReader { geo in
                            let w = geo.size.width
                            let h = geo.size.height
                            let len: CGFloat = 24
                            let pad: CGFloat = 16

                            Canvas { context, size in
                                // Top left
                                var tl1 = Path()
                                tl1.move(to: CGPoint(x: pad + len, y: pad))
                                tl1.addLine(to: CGPoint(x: pad, y: pad))
                                tl1.addLine(to: CGPoint(x: pad, y: pad + len))
                                context.stroke(tl1, with: .color(.yellow.opacity(0.5)), lineWidth: 2)

                                // Top right
                                var tr1 = Path()
                                tr1.move(to: CGPoint(x: w - pad - len, y: pad))
                                tr1.addLine(to: CGPoint(x: w - pad, y: pad))
                                tr1.addLine(to: CGPoint(x: w - pad, y: pad + len))
                                context.stroke(tr1, with: .color(.yellow.opacity(0.5)), lineWidth: 2)

                                // Bottom left
                                var bl1 = Path()
                                bl1.move(to: CGPoint(x: pad + len, y: h - pad))
                                bl1.addLine(to: CGPoint(x: pad, y: h - pad))
                                bl1.addLine(to: CGPoint(x: pad, y: h - pad - len))
                                context.stroke(bl1, with: .color(.yellow.opacity(0.5)), lineWidth: 2)

                                // Bottom right
                                var br1 = Path()
                                br1.move(to: CGPoint(x: w - pad - len, y: h - pad))
                                br1.addLine(to: CGPoint(x: w - pad, y: h - pad))
                                br1.addLine(to: CGPoint(x: w - pad, y: h - pad - len))
                                context.stroke(br1, with: .color(.yellow.opacity(0.5)), lineWidth: 2)
                            }
                        }

                        // Offline / online overlay
                        if statusMonitor.connectionStatus != .online {
                            VStack(spacing: 16) {
                                Image(systemName: "video.slash")
                                    .font(.system(size: 48))
                                    .foregroundColor(.sandTextSecondary)
                                Text("Robot Offline")
                                    .font(.sandHeader)
                                    .foregroundColor(.sandTextSecondary)
                                Text("Connect to your robot to\nview the live camera feed.")
                                    .font(.sandBody)
                                    .foregroundColor(.sandTextSecondary)
                                    .multilineTextAlignment(.center)
                            }
                        } else {
                            VStack(spacing: 16) {
                                Image(systemName: "video.circle")
                                    .font(.system(size: 48))
                                    .foregroundColor(.sandGold.opacity(0.6))
                                Text("Camera Feed")
                                    .font(.sandHeader)
                                    .foregroundColor(.sandTextSecondary)
                                Text("Live feed will appear here\nonce the robot is connected.")
                                    .font(.sandBody)
                                    .foregroundColor(.sandTextSecondary)
                                    .multilineTextAlignment(.center)
                            }
                        }

                        // Status overlay
                        VStack {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    StatusPill(status: statusMonitor.connectionStatus)
                                    if statusMonitor.connectionStatus == .online {
                                        Text("-- fps  --ms")
                                            .font(.sandCaption)
                                            .foregroundColor(.sandTextSecondary)
                                    }
                                }
                                Spacer()
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color.sandError)
                                        .frame(width: 8, height: 8)
                                    Text("LIVE")
                                        .font(.sandCaption)
                                        .foregroundColor(.sandError)
                                }
                                .opacity(statusMonitor.connectionStatus == .online ? 1 : 0.3)
                            }
                            .padding(16)
                            Spacer()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(4/3, contentMode: .fit)

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
