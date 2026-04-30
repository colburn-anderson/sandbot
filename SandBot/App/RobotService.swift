//
//  RobotService.swift
//  SandBot
//
//  Created by Anderson Colburn on 4/16/26.
//

import Foundation

let USE_MOCK_ROBOT = true

protocol RobotServiceProtocol {
    func fetchStatus() async throws -> RobotStatusResponse
    func sendDrawing(_ instruction: DrawingInstruction) async throws -> String
    func fetchJobStatus(jobId: String) async throws -> JobStatus
    func fetchCompletionPhoto(jobId: String) async throws -> Data
    func sendMoveCommand(position: String) async throws
}

final class RobotService {
    static let shared: RobotServiceProtocol = USE_MOCK_ROBOT
        ? MockRobotService()
        : LiveRobotService()
}

final class LiveRobotService: RobotServiceProtocol {
    private var baseURL: String {
        let host = UserDefaults.standard.string(forKey: "robotHost") ?? "sandbot.local"
        return "http://\(host)"
    }

    func fetchStatus() async throws -> RobotStatusResponse {
        let url = URL(string: "\(baseURL)/status")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(RobotStatusResponse.self, from: data)
    }

    func sendDrawing(_ instruction: DrawingInstruction) async throws -> String {
        var request = URLRequest(url: URL(string: "\(baseURL)/draw")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(instruction)
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(SendDrawingResponse.self, from: data)
        return response.jobId
    }

    func fetchJobStatus(jobId: String) async throws -> JobStatus {
        let url = URL(string: "\(baseURL)/job/\(jobId)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(JobStatusResponse.self, from: data)
        return response.status
    }

    func fetchCompletionPhoto(jobId: String) async throws -> Data {
        let url = URL(string: "\(baseURL)/job/\(jobId)/photo")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }

    func sendMoveCommand(position: String) async throws {
        var request = URLRequest(url: URL(string: "\(baseURL)/move")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["position": position])
        _ = try await URLSession.shared.data(for: request)
    }
}

private struct SendDrawingResponse: Codable {
    let accepted: Bool
    let jobId: String
    enum CodingKeys: String, CodingKey {
        case accepted
        case jobId = "job_id"
    }
}

private struct JobStatusResponse: Codable {
    let jobId: String
    let status: JobStatus
    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case status
    }
}
