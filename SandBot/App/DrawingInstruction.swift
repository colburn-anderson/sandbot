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

struct DrawingInstruction: Codable {
    let version: Int
    let source: DrawingSource
    let label: String
    let strokes: [Stroke]
    let bounds: DrawingBounds
    let speed: DrawingSpeed

    struct DrawingBounds: Codable {
        let widthMm: Int
        let heightMm: Int
        enum CodingKeys: String, CodingKey {
            case widthMm = "width_mm"
            case heightMm = "height_mm"
        }
    }
}
