//
//  DrawingInstruction.swift
//  SandBot
//
//  Created by Anderson Colburn on 4/16/26.
//

import Foundation

enum DrawingSource: String, Codable {
    case text, image, aiPattern = "ai_pattern"
}

enum DrawingSpeed: String, Codable {
    case slow, normal, fast
}

enum DrawingTool: String, Codable {
    case rounded  // pass 1 — broad strokes, gentle depth
    case pyramid  // pass 2 — fine detail, precise depth
}

struct ToolCommand: Codable {
    let type: CommandType
    let stroke: Stroke?
    let rotationDegrees: Double?
    
    enum CommandType: String, Codable {
        case stroke       // draw a stroke
        case rotateTool   // switch between rounded/pyramid
    }
    
    static func stroke(_ points: Stroke) -> ToolCommand {
        ToolCommand(type: .stroke, stroke: points, rotationDegrees: nil)
    }
    
    static func rotateTool(degrees: Double) -> ToolCommand {
        ToolCommand(type: .rotateTool, stroke: nil, rotationDegrees: degrees)
    }
}

struct DrawingInstruction: Codable {
    let version: Int
    let source: DrawingSource
    let label: String
    let commands: [ToolCommand]  // replaces flat strokes array
    let bounds: DrawingBounds
    let speed: DrawingSpeed
    let tool: DrawingTool
    
    // Convenience — extract just the strokes for preview
    var strokes: [Stroke] {
        commands.compactMap { $0.stroke }
    }
    
    struct DrawingBounds: Codable {
        let widthMm: Int
        let heightMm: Int
        enum CodingKeys: String, CodingKey {
            case widthMm = "width_mm"
            case heightMm = "height_mm"
        }
    }
}
