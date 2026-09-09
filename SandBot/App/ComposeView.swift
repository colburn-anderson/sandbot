//
//  ComposeView.swift
//  SandBot
//
//  Rewritten for Freenove bridge integration.
//

import SwiftUI
import SwiftData

struct ComposeView: View {
    @EnvironmentObject var statusMonitor: RobotStatusMonitor
    @Environment(\.modelContext) private var modelContext
    @StateObject private var sendManager = SendJobManager()

    @State private var selectedTab: ComposeTab = .text
    @State private var showSendSheet: Bool = false

    // Text state
    @State private var inputText: String = ""
    @State private var fontSize: Double = 80
    @State private var selectedFont: String = "Helvetica-Bold"

    // Image state
    @State private var selectedImage: UIImage? = nil
    @State private var previewImage: UIImage? = nil

    // Shared processing params (matching Freenove GUI defaults)
    @State private var threshold: Double = 151
    @State private var gauss: Double = 3
    @State private var sharpen: Double = 7

    enum ComposeTab { case text, image, ai }

    var canSend: Bool {
        switch selectedTab {
        case .text:
            return !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .image:
            return selectedImage != nil
        case .ai:
            return !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var sendLabel: String {
        switch selectedTab {
        case .text: return inputText.isEmpty ? "Drawing" : inputText
        case .image: return "Image Drawing"
        case .ai: return inputText.isEmpty ? "AI Pattern" : inputText
        }
    }

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
                            Text("Pattern").tag(ComposeTab.ai)
                        }
                        .pickerStyle(.segmented)
                        .padding()

                        // Input area
                        switch selectedTab {
                        case .text:
                            TextDrawView(inputText: $inputText, fontSize: $fontSize, selectedFont: $selectedFont)
                        case .image:
                            ImageDrawView(
                                previewImage: $previewImage,
                                selectedImage: $selectedImage,
                                threshold: $threshold,
                                gauss: $gauss,
                                sharpen: $sharpen
                            )
                        case .ai:
                            AIPatternView(strokes: .constant([]), inputLabel: $inputText)
                        }

                        // Send button
                        PrimaryButton(
                            title: "Send to Robot",
                            action: { showSendSheet = true },
                            isDisabled: !canSend || statusMonitor.connectionStatus == .offline
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
                    selectedTab: selectedTab,
                    inputText: sendLabel,
                    fontSize: Int(fontSize),
                    selectedFont: selectedFont,
                    selectedImage: selectedImage,
                    threshold: Int(threshold),
                    gauss: Int(gauss),
                    sharpen: Int(sharpen),
                    penUpHeight: 30,
                    sendManager: sendManager
                )
                .onDisappear { sendManager.reset() }
            }
        }
    }
}
