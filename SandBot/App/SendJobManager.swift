//
//  SendJobManager.swift
//  SandBot
//
//  Created by Anderson Colburn on 4/19/26.
//

import Foundation
import Combine
import SwiftData

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
    
    func send(instruction: DrawingInstruction, context: ModelContext) async {
        sendState = .connecting
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        sendState = .sending
        do {
            let jobId = try await RobotService.shared.sendDrawing(instruction)
            sendState = .queued
            try? await Task.sleep(nanoseconds: 600_000_000)
            sendState = .success(jobId: jobId)
            
            // Save to history
            let strokesData = (try? JSONEncoder().encode(instruction.strokes)) ?? Data()
            let entry = DrawingHistoryEntry(
                sourceType: instruction.source.rawValue,
                label: instruction.label,
                strokesData: strokesData,
                jobId: jobId
            )
            context.insert(entry)
            try? context.save()
            
            // Poll for completion in background
            Task {
                await pollForCompletion(entry: entry, context: context)
            }
            
        } catch {
            sendState = .failed(error.localizedDescription)
        }
    }
    
    func reset() {
        sendState = .idle
    }
    
    private func pollForCompletion(entry: DrawingHistoryEntry, context: ModelContext) async {
        guard let jobId = entry.jobId else { return }
        var attempts = 0
        while attempts < 20 {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            do {
                let status = try await RobotService.shared.fetchJobStatus(jobId: jobId)
                entry.status = status
                try? context.save()
                if status == .completed {
                    let photo = try await RobotService.shared.fetchCompletionPhoto(jobId: jobId)
                    entry.completionPhotoData = photo
                    try? context.save()
                    return
                } else if status == .failed {
                    return
                }
            } catch {
                break
            }
            attempts += 1
        }
    }
}
