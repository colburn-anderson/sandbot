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
}

typealias Stroke = [StrokePoint]
