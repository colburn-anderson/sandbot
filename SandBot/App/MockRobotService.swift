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

    func sendImage(_ image: UIImage, threshold: Int, gauss: Int, sharpen: Int, penUpHeight: Int, label: String) async throws -> String {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        return "mock-\(UUID().uuidString.prefix(6))"
    }

    func sendText(_ text: String, fontSize: Int, fontName: String, threshold: Int, gauss: Int, sharpen: Int, penUpHeight: Int) async throws -> String {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        return "mock-\(UUID().uuidString.prefix(6))"
    }

    func fetchPreview(_ image: UIImage, threshold: Int, gauss: Int, sharpen: Int) async throws -> UIImage {
        try await Task.sleep(nanoseconds: 500_000_000)
        // Return a simple placeholder
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 200))
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
            UIColor.black.setStroke()
            let path = UIBezierPath(ovalIn: CGRect(x: 50, y: 25, width: 300, height: 150))
            path.stroke()
        }
    }

    func fetchJobStatus(jobId: String) async throws -> JobStatus {
        try await Task.sleep(nanoseconds: 500_000_000)
        return .completed
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
}
