//
//  StatusPill.swift
//  SandBot
//
//  Created by Anderson Colburn on 4/16/26.
//

import SwiftUI

enum RobotConnectionStatus {
    case online, connecting, offline

    var label: String {
        switch self {
        case .online:     return "ONLINE"
        case .connecting: return "CONNECTING"
        case .offline:    return "OFFLINE"
        }
    }

    var color: Color {
        switch self {
        case .online:     return Color.sandSuccess
        case .connecting: return Color.sandGold
        case .offline:    return Color.sandError
        }
    }
}

struct StatusPill: View {
    let status: RobotConnectionStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status.color)
                .frame(width: 7, height: 7)
            Text(status.label)
                .font(.sandCaption)
                .foregroundColor(status.color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(status.color.opacity(0.12)))
        .overlay(Capsule().stroke(status.color.opacity(0.3), lineWidth: 1))
    }
}
