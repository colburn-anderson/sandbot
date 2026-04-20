//
//  ComposeView.swift
//  SandBot
//
//  Created by Anderson Colburn on 4/16/26.
//

import SwiftUI

struct ComposeView: View {
    @EnvironmentObject var statusMonitor: RobotStatusMonitor
    @State private var strokes: [Stroke] = []
    @State private var selectedTab: ComposeTab = .text

    enum ComposeTab { case text, image, ai }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sandBgPrimary.ignoresSafeArea()
                VStack(spacing: 0) {

                    // Tab picker
                    Picker("Mode", selection: $selectedTab) {
                        Text("Text").tag(ComposeTab.text)
                        Text("Image").tag(ComposeTab.image)
                        Text("AI Pattern").tag(ComposeTab.ai)
                    }
                    .pickerStyle(.segmented)
                    .padding()

                    // Input area (scrollable)
                    ScrollView {
                        switch selectedTab {
                        case .text:
                            TextDrawView(strokes: $strokes)
                        case .image:
                            Text("Image — coming soon")
                                .foregroundColor(.sandTextSecondary)
                                .padding()
                        case .ai:
                            Text("AI Pattern — coming soon")
                                .foregroundColor(.sandTextSecondary)
                                .padding()
                        }
                    }
                    .frame(maxHeight: 220)

                    // Canvas preview — outside scroll, full width
                    SandCanvas(strokes: strokes)

                    // Send button
                    PrimaryButton(
                        title: "Send to Robot",
                        action: { },
                        isDisabled: strokes.isEmpty || statusMonitor.connectionStatus == .offline
                    )
                    .padding()
                }
            }
            .navigationTitle("SandBot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    StatusPill(status: statusMonitor.connectionStatus)
                }
            }
        }
    }
}
