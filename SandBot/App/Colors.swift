//
//  Colors.swift
//  SandBot
//
//  Created by Anderson Colburn on 4/16/26.
//

import SwiftUI

extension Color {
    static let sandBgPrimary   = Color(hex: "#1A1610")
    static let sandBgSecondary = Color(hex: "#231E17")
    static let sandSurface     = Color(hex: "#2E2820")
    static let sandBorder      = Color(hex: "#4A3F30")
    static let sandGold        = Color(hex: "#E8B84B")
    static let sandOrange      = Color(hex: "#D4763A")
    static let sandTextPrimary   = Color(hex: "#F0E8D8")
    static let sandTextSecondary = Color(hex: "#8C7B65")
    static let sandSuccess = Color(hex: "#5DB87A")
    static let sandError   = Color(hex: "#C0392B")

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
    }
}
