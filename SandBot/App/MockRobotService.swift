//
//  MockRobotService.swift
//  SandBot
//
//  Created by Anderson Colburn on 4/16/26.
//


import Foundation

final class MockRobotService: RobotServiceProtocol {
    func fetchStatus() async throws -> RobotStatusResponse {
        try await Task.sleep(nanoseconds: 300_000_000)
        return RobotStatusResponse(state: .idle, queueLength: 0)
    }

    func sendDrawing(_ instruction: DrawingInstruction) async throws -> String {
        try await Task.sleep(nanoseconds: 800_000_000)
        return "mock-job-\(UUID().uuidString.prefix(8))"
    }

    func fetchJobStatus(jobId: String) async throws -> JobStatus {
        try await Task.sleep(nanoseconds: 500_000_000)
        return .completed
    }

    func fetchCompletionPhoto(jobId: String) async throws -> Data {
        try await Task.sleep(nanoseconds: 400_000_000)
        let png1x1 = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")!
        return png1x1
    }

    func sendMoveCommand(position: String) async throws {
        try await Task.sleep(nanoseconds: 200_000_000)
    }
}