//
//  MockRobotService.swift
//  SandBot
//
//  Mock implementation matching the new RobotServiceProtocol.
//

import Foundation
import UIKit

final class MockRobotService: RobotServiceProtocol {
    func fetchStatus() async throws -> RobotStatusResponse {
        try await Task.sleep(nanoseconds: 200_000_000)
        return RobotStatusResponse(state: .idle, queueLength: 0)
    }

    func sendImage(_ image: UIImage, threshold: Int, gauss: Int, sharpen: Int, penUpHeight: Int, label: String, layout: DrawingLayout) async throws -> String {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        return "mock-\(UUID().uuidString.prefix(6))"
    }

    func sendText(_ text: String, fontSize: Int, fontName: String, threshold: Int, gauss: Int, sharpen: Int, penUpHeight: Int, layout: DrawingLayout) async throws -> String {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        return "mock-\(UUID().uuidString.prefix(6))"
    }

    func fetchAutoSettings(_ image: UIImage) async throws -> ImageSettings {
        .defaults
    }

    func fetchImagePreview(_ image: UIImage, threshold: Int, gauss: Int, sharpen: Int, layout: DrawingLayout) async throws -> PreviewStrokes {
        throw RobotError.invalidResponse  // falls back to the on-device preview
    }

    func fetchJob(jobId: String) async throws -> JobReport {
        try await Task.sleep(nanoseconds: 500_000_000)
        return JobReport(status: .completed, error: nil)
    }

    func connectArm() async throws {
        try await Task.sleep(nanoseconds: 300_000_000)
    }

    func loadMotors() async throws {
        try await Task.sleep(nanoseconds: 300_000_000)
    }

    func relaxMotors() async throws {
        try await Task.sleep(nanoseconds: 300_000_000)
    }

    func stopArm() async throws {
        try await Task.sleep(nanoseconds: 300_000_000)
    }

    func sendMoveCommand(position: String) async throws {
        try await Task.sleep(nanoseconds: 500_000_000)
    }

    func fetchBoundary() async throws -> PitBoundary {
        .default
    }

    func fetchJobPhoto(jobId: String) async throws -> Data? {
        nil
    }

    func fetchTextPreview(_ text: String, fontSize: Int, fontName: String, layout: DrawingLayout) async throws -> PreviewStrokes {
        throw RobotError.invalidResponse  // falls back to the on-device preview
    }
}
