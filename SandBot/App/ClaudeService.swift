import Foundation

final class ClaudeService {
    static let shared = ClaudeService()

    private let apiKey: String = {
        Bundle.main.infoDictionary?["ANTHROPIC_API_KEY"] as? String ?? ""
    }()

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
            Each stroke is an array of {"x": float, "y": float} objects with values between 0.0 and 1.0,
            representing normalized coordinates on a square drawing surface.
            
            Guidelines:
            - Generate complex, detailed patterns with many strokes and points
            - Fill the entire 0.0-1.0 space well
            - For geometric patterns, be mathematically precise
            - Each stroke should be a continuous path (pen down, draw, pen up)
            - Aim for 20-100 strokes with many points each for rich detail
            - No explanation. No markdown. Only raw JSON array.
            """

        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 8000,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": description]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ClaudeError.badResponse
        }

        let decoded = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        guard let text = decoded.content.first?.text else {
            throw ClaudeError.emptyResponse
        }

        let clean = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = clean.data(using: .utf8) else {
            throw ClaudeError.parseError
        }

        return try JSONDecoder().decode([Stroke].self, from: jsonData)
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
    struct ContentBlock: Codable {
        let type: String
        let text: String?
    }
}