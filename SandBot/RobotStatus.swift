//
//  RobotStatus.swift
//  SandBot
//
//  Created by Anderson Colburn on 4/16/26.
//

import Foundation

struct RobotStatusResponse: Codable {
    let state: RobotState
    let queueLength: Int
    enum CodingKeys: String, CodingKey {
        case state
        case queueLength = "queue_length"
    }
}

enum RobotState: String, Codable {
    case idle, drawing, error
}
