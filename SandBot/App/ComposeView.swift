//
//  ComposeView.swift
//  SandBot
//
//  Created by Anderson Colburn on 4/16/26.
//

import SwiftUI
import SwiftData

struct ComposeView: View {
    @EnvironmentObject var statusMonitor: RobotStatusMonitor
    @Environment(\.modelContext) private var modelContext
    @StateObject private var sendManager = SendJobManager()
    
    @State private var strokes: [Stroke] = []
    @State private var selectedTab: ComposeTab = .text
    @State private var inputText: String = ""
    @State private var showSendSheet: Bool = false

    enum ComposeTab { case text, image, ai }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sandBgPrimary.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 0) {

                        // Tab picker
                        Picker("Mode", selection: $selectedTab) {
                            Text("Text").tag(ComposeTab.text)
                            Text("Image").tag(ComposeTab.image)
                            Text("AI Pattern").tag(ComposeTab.ai)
                        }
                        .pickerStyle(.segmented)
                        .padding()

                        // Input area
                        switch selectedTab {
                        case .text:
                            TextDrawView(strokes: $strokes, inputText: $inputText)
                        case .image:
                            ImageDrawView(strokes: $strokes)
                        case .ai:
                            AIPatternView(strokes: $strokes, inputLabel: $inputText)
                        }

                        // Canvas preview
                        SandCanvas(strokes: strokes)
                            .padding(.top, 8)

                        // Send button
                        PrimaryButton(
                            title: "Send to Robot",
                            action: { showSendSheet = true },
                            isDisabled: strokes.isEmpty || statusMonitor.connectionStatus == .offline
                        )
                        .padding()
                    }
                }
            }
            .navigationTitle("SandBot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    StatusPill(status: statusMonitor.connectionStatus)
                }
            }
            .sheet(isPresented: $showSendSheet) {
                SendSheet(
                    strokes: strokes,
                    label: inputText.isEmpty ? "Drawing" : inputText,
                    source: selectedTab == .ai ? .aiPattern : .text,
                    sendManager: sendManager
                )
                .onDisappear { sendManager.reset() }
            }
        }
    }
}
