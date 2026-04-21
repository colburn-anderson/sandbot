//
//  Stroke.swift
//  SandBot
//
//  Created by Anderson Colburn on 4/16/26.
//

import Foundation

struct StrokePoint: Codable, Equatable {
    let x: Double
    let y: Double
    let z: Double // 0.0 = surface skim, 1.0 = deepest press
    
    init(x: Double, y: Double, z: Double = 0.5) {
        self.x = x
        self.y = y
        self.z = z
    }
}

typealias Stroke = [StrokePoint]
