//
//  RobotService.swift
//  SandBot
//
//  Rewritten for Freenove bridge server integration.
//  The bridge handles all image processing and G-code generation.
//

import Foundation
import UIKit

let USE_MOCK_ROBOT = false

// MARK: - Protocol

protocol RobotServiceProtocol {
    func fetchStatus() async throws -> RobotStatusResponse
    func sendImage(_ image: UIImage, threshold: Int, gauss: Int, sharpen: Int, penUpHeight: Int, label: String) async throws -> String
    func sendText(_ text: String, fontSize: Int, fontName: String, threshold: Int, gauss: Int, sharpen: Int, penUpHeight: Int) async throws -> String
    func fetchPreview(_ image: UIImage, threshold: Int, gauss: Int, sharpen: Int) async throws -> UIImage
    func fetchJobStatus(jobId: String) async throws -> JobStatus
    func connectArm() async throws
    func loadMotors() async throws
    func relaxMotors() async throws
    func stopArm() async throws
    func sendMoveCommand(position: String) async throws
}

// MARK: - Shared instance

final class RobotService {
    static let shared: RobotServiceProtocol = USE_MOCK_ROBOT
        ? MockRobotService()
        : LiveRobotService()
}

// MARK: - Live implementation

final class LiveRobotService: RobotServiceProtocol {
    private var baseURL: String {
        let host = UserDefaults.standard.string(forKey: "robotHost") ?? "100.95.15.84:8080"
        return "http://\(host)"
    }

    // MARK: Status

    func fetchStatus() async throws -> RobotStatusResponse {
        let url = URL(string: "\(baseURL)/status")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(RobotStatusResponse.self, from: data)
    }

    // MARK: Send image for drawing

    func sendImage(_ image: UIImage, threshold: Int, gauss: Int, sharpen: Int, penUpHeight: Int, label: String) async throws -> String {
        let url = URL(string: "\(baseURL)/draw")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Image file
        guard let imageData = image.jpegData(compressionQuality: 0.9) else {
            throw RobotError.invalidImage
        }
        body.appendMultipart(name: "image", filename: "drawing.jpg", mimeType: "image/jpeg", data: imageData, boundary: boundary)

        // Parameters
        body.appendMultipartField(name: "threshold", value: "\(threshold)", boundary: boundary)
        body.appendMultipartField(name: "gauss", value: "\(gauss)", boundary: boundary)
        body.appendMultipartField(name: "sharpen", value: "\(sharpen)", boundary: boundary)
        body.appendMultipartField(name: "pen_up_height", value: "\(penUpHeight)", boundary: boundary)
        body.appendMultipartField(name: "label", value: label, boundary: boundary)

        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(DrawResponse.self, from: data)

        if let error = response.error {
            throw RobotError.serverError(error)
        }

        return response.jobId ?? ""
    }

    // MARK: Send text for drawing

    func sendText(_ text: String, fontSize: Int, fontName: String, threshold: Int, gauss: Int, sharpen: Int, penUpHeight: Int) async throws -> String {
        let url = URL(string: "\(baseURL)/draw")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "text": text,
            "font_name": fontName,
            "font_size": fontSize,
            "threshold": threshold,
            "gauss": gauss,
            "sharpen": sharpen,
            "pen_up_height": penUpHeight
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(DrawResponse.self, from: data)

        if let error = response.error {
            throw RobotError.serverError(error)
        }

        return response.jobId ?? ""
    }

    // MARK: Preview contours (image only)

    func fetchPreview(_ image: UIImage, threshold: Int, gauss: Int, sharpen: Int) async throws -> UIImage {
        let url = URL(string: "\(baseURL)/preview")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        guard let imageData = image.jpegData(compressionQuality: 0.9) else {
            throw RobotError.invalidImage
        }
        body.appendMultipart(name: "image", filename: "preview.jpg", mimeType: "image/jpeg", data: imageData, boundary: boundary)
        body.appendMultipartField(name: "threshold", value: "\(threshold)", boundary: boundary)
        body.appendMultipartField(name: "gauss", value: "\(gauss)", boundary: boundary)
        body.appendMultipartField(name: "sharpen", value: "\(sharpen)", boundary: boundary)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let resultImage = UIImage(data: data) else {
            throw RobotError.invalidResponse
        }

        return resultImage
    }

    // MARK: Job status

    func fetchJobStatus(jobId: String) async throws -> JobStatus {
        let url = URL(string: "\(baseURL)/job/\(jobId)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(JobStatusResponse.self, from: data)
        return response.status
    }

    // MARK: Arm control

    func connectArm() async throws {
        var request = URLRequest(url: URL(string: "\(baseURL)/connect")!)
        request.httpMethod = "POST"
        _ = try await URLSession.shared.data(for: request)
    }

    func loadMotors() async throws {
        var request = URLRequest(url: URL(string: "\(baseURL)/load")!)
        request.httpMethod = "POST"
        _ = try await URLSession.shared.data(for: request)
    }

    func relaxMotors() async throws {
        var request = URLRequest(url: URL(string: "\(baseURL)/relax")!)
        request.httpMethod = "POST"
        _ = try await URLSession.shared.data(for: request)
    }

    func stopArm() async throws {
        var request = URLRequest(url: URL(string: "\(baseURL)/stop")!)
        request.httpMethod = "POST"
        _ = try await URLSession.shared.data(for: request)
    }

    func sendMoveCommand(position: String) async throws {
        var request = URLRequest(url: URL(string: "\(baseURL)/move")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["position": position])
        _ = try await URLSession.shared.data(for: request)
    }
}

// MARK: - Response models

struct DrawResponse: Codable {
    let accepted: Bool?
    let jobId: String?
    let error: String?
    let gcodeCount: Int?

    enum CodingKeys: String, CodingKey {
        case accepted
        case jobId = "job_id"
        case error
        case gcodeCount = "gcode_count"
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

// MARK: - Errors

enum RobotError: LocalizedError {
    case invalidImage
    case invalidResponse
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "Could not process image"
        case .invalidResponse: return "Invalid response from robot"
        case .serverError(let msg): return msg
        }
    }
}

// MARK: - Data helpers for multipart form

extension Data {
    mutating func appendMultipart(name: String, filename: String, mimeType: String, data: Data, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }

    mutating func appendMultipartField(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }
}
