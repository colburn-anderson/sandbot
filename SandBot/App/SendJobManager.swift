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
    /// True while the robot can't be reached mid-job. The Pi keeps drawing on
    /// its own; we keep polling and pick the job back up when it reappears.
    @Published var isReconnecting = false
    @Published private(set) var isStopping = false

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
            let entry = saveHistory(label: label, source: "image", jobId: jobId, context: context)

            await pollUntilDone(jobId: jobId, entry: entry, context: context)

        } catch {
            sendState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Send Text

    func sendText(text: String, fontSize: Int, fontName: String, threshold: Int, gauss: Int, sharpen: Int, penUpHeight: Int, layout: TextLayout = TextLayout(), context: ModelContext) async {
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
                penUpHeight: penUpHeight,
                layout: layout
            )

            sendState = .queued
            let entry = saveHistory(label: text, source: "text", jobId: jobId, context: context)

            await pollUntilDone(jobId: jobId, entry: entry, context: context)

        } catch {
            sendState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Reset

    func reset() {
        sendState = .idle
        isReconnecting = false
        isStopping = false
    }

    /// Graceful stop: the Pi finishes the few queued moves, lifts, tucks up
    /// and unloads. Polling then reports the job as stopped.
    func stop() async {
        isStopping = true
        do {
            try await RobotService.shared.stopArm()
        } catch {
            isStopping = false
        }
    }

    // MARK: - Catch up on jobs that finished while the app wasn't watching

    /// Re-check History entries still marked sent/drawing (app closed, lost
    /// connection, timed out) and pull in their status and photo.
    static func refreshUnfinished(_ entries: [DrawingHistoryEntry], context: ModelContext) async {
        for entry in entries where entry.status == .sent || entry.status == .drawing {
            guard let jobId = entry.jobId, !jobId.isEmpty else { continue }
            do {
                switch try await RobotService.shared.fetchJobStatus(jobId: jobId) {
                case .completed:
                    entry.status = .completed
                    if entry.completionPhotoData == nil {
                        entry.completionPhotoData = try? await RobotService.shared.fetchJobPhoto(jobId: jobId)
                    }
                case .failed:
                    entry.status = .failed
                case .drawing, .sent:
                    entry.status = .drawing
                }
            } catch RobotError.jobNotFound {
                // Robot restarted since; the photo may still be on disk.
                if let photo = try? await RobotService.shared.fetchJobPhoto(jobId: jobId) {
                    entry.completionPhotoData = photo
                    entry.status = .completed
                } else {
                    entry.status = .failed
                }
            } catch {
                return  // robot unreachable — try again next time
            }
        }
        try? context.save()
    }

    // MARK: - History

    @discardableResult
    private func saveHistory(label: String, source: String, jobId: String, context: ModelContext) -> DrawingHistoryEntry {
        let entry = DrawingHistoryEntry(
            sourceType: source,
            label: label,
            strokesData: Data(),
            jobId: jobId
        )
        context.insert(entry)
        try? context.save()
        return entry
    }

    // MARK: - Polling (this is what actually drives the UI state now)

    private func pollUntilDone(jobId: String, entry: DrawingHistoryEntry, context: ModelContext) async {
        // Give the bridge a moment to transition the job to "drawing"
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        sendState = .drawing

        let started = Date()
        var lastContact = Date()
        let maxSilence: TimeInterval = 20 * 60   // unreachable this long → give up
        let maxTotal: TimeInterval = 90 * 60     // big drawings can take a while

        while Date().timeIntervalSince(started) < maxTotal,
              Date().timeIntervalSince(lastContact) < maxSilence {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            do {
                let status = try await RobotService.shared.fetchJobStatus(jobId: jobId)
                lastContact = Date()
                isReconnecting = false
                switch status {
                case .completed:
                    entry.status = .completed
                    // The Pi parks at the camera view and photographs the result.
                    entry.completionPhotoData = try? await RobotService.shared.fetchJobPhoto(jobId: jobId)
                    try? context.save()
                    sendState = .success(jobId: jobId)
                    return
                case .failed:
                    entry.status = .failed
                    try? context.save()
                    sendState = .failed(isStopping
                        ? "Stopped. The arm tucked up and turned its motors off."
                        : "The drawing failed partway through.")
                    isStopping = false
                    return
                case .drawing, .sent:
                    // Still going — keep the in-progress screen up
                    sendState = .drawing
                }
            } catch RobotError.jobNotFound {
                isReconnecting = false
                sendState = .failed("The robot restarted and lost track of this drawing. Check the pit.")
                return
            } catch {
                // Network hiccup — the Pi keeps drawing; keep trying.
                isReconnecting = true
            }
        }

        isReconnecting = false
        // History re-checks unfinished jobs later, so nothing is lost.
        sendState = .failed("Couldn't reach the robot for a while. History will update when it's back.")
    }
}
