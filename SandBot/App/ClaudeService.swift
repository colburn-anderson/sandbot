//
//  ClaudeService.swift
//  SandBot
//
//  Created by Anderson Colburn on 4/19/26.
//

import Foundation

final class ClaudeService {
    static let shared = ClaudeService()

    private let apiKey = Config.anthropicAPIKey

    func generatePattern(description: String) async throws -> [Stroke] {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let systemPrompt = """
            You are a drawing path generator for a sand-drawing robot.
            The user will describe a pattern or shape.
            Respond ONLY with a valid JSON array of strokes.
            Each stroke is an array of {"x": float, "y": float} objects with values between 0.0 and 1.0.
            Guidelines:
            - Generate exactly 10-15 strokes with exactly 15-20 points each
            - Keep total response under 3000 tokens
            - Fill the 0.0-1.0 space well
            - IMPORTANT: Always complete the full JSON array, never cut off mid-stroke
            - No explanation. No markdown. Only raw JSON array.
            """

        let body: [String: Any] = [
            "model": "claude-sonnet-4-5",
            "max_tokens": 4000,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": description]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 60
        let session = URLSession(configuration: config)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeError.badResponse
        }

        if httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "unknown"
            print("Claude API error \(httpResponse.statusCode): \(errorText)")
            throw ClaudeError.badResponse
        }

        let decoded = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        
        if let usage = decoded.usage {
            print("Tokens used — input: \(usage.inputTokens) output: \(usage.outputTokens)")
        }

        guard let text = decoded.content.first?.text else {
            throw ClaudeError.emptyResponse
        }

        let clean = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        print("Claude raw response: \(clean.prefix(500))")

        guard let jsonData = clean.data(using: .utf8) else {
            throw ClaudeError.parseError
        }

        do {
            return try JSONDecoder().decode([Stroke].self, from: jsonData)
        } catch {
            print("JSON decode error: \(error)")
            throw ClaudeError.parseError
        }
    }
}

enum ClaudeError: LocalizedError {
    case badResponse, emptyResponse, parseError

    var errorDescription: String? {
        switch self {
        case .badResponse:   return "Claude API returned an error. Check your API key."
        case .emptyResponse: return "Claude returned an empty response."
        case .parseError:    return "Couldn't parse Claude's pattern output."
        }
    }
}

private struct ClaudeResponse: Codable {
    let content: [ContentBlock]
    let usage: Usage?

    struct ContentBlock: Codable {
        let type: String
        let text: String?
    }

    struct Usage: Codable {
        let inputTokens: Int
        let outputTokens: Int
        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }
}
