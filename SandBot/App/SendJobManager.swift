//
//  SendJobManager.swift
//  SandBot
//
//  Fixed: properly waits for actual completion before showing success.
//

import Foundation
import Combine
import SwiftData
import UIKit

enum SendState: Equatable {
    case idle
    case connecting
    case sending
    case queued
    case drawing
    case success(jobId: String)
    case failed(String)
}

@MainActor
final class SendJobManager: ObservableObject {
    @Published var sendState: SendState = .idle

    // MARK: - Send Image

    func sendImage(image: UIImage, threshold: Int, gauss: Int, sharpen: Int, penUpHeight: Int, label: String, context: ModelContext) async {
        sendState = .connecting
        try? await Task.sleep(nanoseconds: 300_000_000)

        sendState = .sending
        do {
            let jobId = try await RobotService.shared.sendImage(
                image,
                threshold: threshold,
                gauss: gauss,
                sharpen: sharpen,
                penUpHeight: penUpHeight,
                label: label
            )

            sendState = .queued
            saveHistory(label: label, source: "image", jobId: jobId, context: context)

            await pollUntilDone(jobId: jobId)

        } catch {
            sendState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Send Text

    func sendText(text: String, fontSize: Int, fontName: String, threshold: Int, gauss: Int, sharpen: Int, penUpHeight: Int, context: ModelContext) async {
        sendState = .connecting
        try? await Task.sleep(nanoseconds: 300_000_000)

        sendState = .sending
        do {
            let jobId = try await RobotService.shared.sendText(
                text,
                fontSize: fontSize,
                fontName: fontName,
                threshold: threshold,
                gauss: gauss,
                sharpen: sharpen,
                penUpHeight: penUpHeight
            )

            sendState = .queued
            saveHistory(label: text, source: "text", jobId: jobId, context: context)

            await pollUntilDone(jobId: jobId)

        } catch {
            sendState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Reset

    func reset() {
        sendState = .idle
    }

    // MARK: - History

    private func saveHistory(label: String, source: String, jobId: String, context: ModelContext) {
        let entry = DrawingHistoryEntry(
            sourceType: source,
            label: label,
            strokesData: Data(),
            jobId: jobId
        )
        context.insert(entry)
        try? context.save()
    }

    // MARK: - Polling (this is what actually drives the UI state now)

    private func pollUntilDone(jobId: String) async {
        // Give the bridge a moment to transition the job to "drawing"
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        sendState = .drawing

        var attempts = 0
        let maxAttempts = 120  // up to 10 minutes at 5s intervals

        while attempts < maxAttempts {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            do {
                let status = try await RobotService.shared.fetchJobStatus(jobId: jobId)
                switch status {
                case .completed:
                    sendState = .success(jobId: jobId)
                    return
                case .failed:
                    sendState = .failed("The drawing failed partway through.")
                    return
                case .drawing, .sent:
                    // Still going — keep the in-progress screen up
                    sendState = .drawing
                }
            } catch {
                // Network hiccup — don't fail immediately, just keep trying
            }
            attempts += 1
        }

        // Timed out waiting — let the user know rather than hanging forever
        sendState = .failed("Taking longer than expected. Check History for status.")
    }
}
