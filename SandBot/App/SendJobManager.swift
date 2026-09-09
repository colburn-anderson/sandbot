//
//  SendJobManager.swift
//  SandBot
//
//  Rewritten for Freenove bridge integration.
//

import Foundation
import Combine
import SwiftData
import UIKit

enum SendState {
    case idle
    case connecting
    case sending
    case queued
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
            try? await Task.sleep(nanoseconds: 500_000_000)
            sendState = .success(jobId: jobId)

            // Save to history
            saveHistory(label: label, source: "image", jobId: jobId, context: context)

            // Poll for completion
            Task { await pollForCompletion(jobId: jobId, context: context) }

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
            try? await Task.sleep(nanoseconds: 500_000_000)
            sendState = .success(jobId: jobId)

            // Save to history
            saveHistory(label: text, source: "text", jobId: jobId, context: context)

            // Poll for completion
            Task { await pollForCompletion(jobId: jobId, context: context) }

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

    // MARK: - Polling

    private func pollForCompletion(jobId: String, context: ModelContext) async {
        var attempts = 0
        while attempts < 60 {  // up to 5 minutes
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            do {
                let status = try await RobotService.shared.fetchJobStatus(jobId: jobId)
                if status == .completed || status == .failed {
                    return
                }
            } catch {
                break
            }
            attempts += 1
        }
    }
}
