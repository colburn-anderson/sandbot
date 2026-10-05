//
//  SendSheet.swift
//  SandBot
//
//  Rewritten for Freenove bridge integration.
//  Sends images or text directly to the bridge for processing + drawing.
//

import SwiftUI
import SwiftData

struct SendSheet: View {
    let selectedTab: ComposeView.ComposeTab
    let inputText: String
    let fontSize: Int
    let selectedFont: String
    var textLayout = DrawingLayout()
    var imageLayout = DrawingLayout()
    let selectedImage: UIImage?
    let threshold: Int
    let gauss: Int
    let sharpen: Int
    let penUpHeight: Int
    @ObservedObject var sendManager: SendJobManager

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var label: String {
        inputText.isEmpty ? "Drawing" : inputText
    }

    var body: some View {
        ZStack {
            Color.sandBgPrimary.ignoresSafeArea()
            VStack(spacing: 32) {
                Spacer()

                // Status icon
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 80, height: 80)
                    Image(systemName: iconName)
                        .font(.system(size: 32))
                        .foregroundColor(iconColor)
                }

                // Status text
                VStack(spacing: 8) {
                    Text(titleText)
                        .font(.sandHeader)
                        .foregroundColor(.sandTextPrimary)
                    Text(subtitleText)
                        .font(.sandBody)
                        .foregroundColor(.sandTextSecondary)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                // Action buttons
                switch sendManager.sendState {
                case .idle:
                    PrimaryButton(title: "Confirm Send", action: sendNow)
                    PrimaryButton(title: "Cancel", action: { dismiss() }, style: .secondary)

                case .connecting, .sending, .queued, .drawing:
                    ProgressView()
                        .tint(Color.sandGold)
                    if case .drawing = sendManager.sendState {
                        PrimaryButton(
                            title: sendManager.isStopping ? "Stopping…" : "Stop Drawing",
                            action: { Task { await sendManager.stop() } },
                            isDisabled: sendManager.isStopping
                        )
                    }
                    // Closing is safe: the robot finishes and History catches up later.
                    PrimaryButton(title: "Close", action: { dismiss() }, style: .secondary)

                case .success:
                    PrimaryButton(title: "Done", action: { dismiss() })

                case .failed:
                    PrimaryButton(title: "Retry", action: sendNow)
                    PrimaryButton(title: "Cancel", action: { dismiss() }, style: .secondary)
                }
            }
            .padding(32)
        }
        .presentationDetents([.medium])
    }

    private var iconName: String {
        switch sendManager.sendState {
        case .idle:        return "paperplane"
        case .connecting:  return "wifi"
        case .sending:     return "arrow.up.circle"
        case .queued:      return "clock"
        case .success:     return "checkmark.circle.fill"
        case .failed:      return "xmark.circle.fill"
        case .drawing:     return "pencil.and.outline"
        }
    }

    private var iconColor: Color {
        switch sendManager.sendState {
        case .idle, .connecting, .sending, .queued, .drawing: return Color.sandGold
        case .success:  return Color.sandSuccess
        case .failed:   return Color.sandError
        }
    }

    private var titleText: String {
        switch sendManager.sendState {
        case .idle:       return "Ready to Send"
        case .connecting: return "Connecting..."
        case .sending:    return "Sending..."
        case .queued:     return "Drawing Started!"
        case .success:    return "Drawing Complete!"
        case .failed:     return "Failed"
        case .drawing:    return "Drawing..."
        }
    }

    private var subtitleText: String {
        switch sendManager.sendState {
        case .idle:       return "\"\(label)\"\nwill be sent to the robot."
        case .connecting: return "Reaching your robot..."
        case .sending:    return "Uploading and processing..."
        case .queued:     return "The robot is drawing now."
        case .success:    return "Check History for updates."
        case .drawing:
            if sendManager.isStopping {
                return "Stopping — finishing the last few moves, then lifting and tucking up."
            }
            if sendManager.isReconnecting {
                return "Lost connection to the robot — it keeps drawing on its own. Reconnecting…"
            }
            return "The robot is drawing your \(label.isEmpty ? "creation" : "design") right now."
        case .failed(let msg): return msg
        }
    }

    private func sendNow() {
        Task {
            switch selectedTab {
            case .image:
                guard let image = selectedImage else { return }
                await sendManager.sendImage(
                    image: image,
                    threshold: threshold,
                    gauss: gauss,
                    sharpen: sharpen,
                    penUpHeight: penUpHeight,
                    label: label,
                    layout: imageLayout,
                    context: modelContext
                )
            case .text:
                await sendManager.sendText(
                    text: inputText,
                    fontSize: fontSize,
                    fontName: selectedFont,
                    threshold: threshold,
                    gauss: gauss,
                    sharpen: sharpen,
                    penUpHeight: penUpHeight,
                    layout: textLayout,
                    context: modelContext
                )
            case .ai:
                // AI patterns can use text endpoint for now
                await sendManager.sendText(
                    text: inputText,
                    fontSize: fontSize,
                    fontName: selectedFont,
                    threshold: threshold,
                    gauss: gauss,
                    sharpen: sharpen,
                    penUpHeight: penUpHeight,
                    context: modelContext
                )
                
            }
        }
    }
}
