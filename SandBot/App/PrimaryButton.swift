//
//  PrimaryButton.swift
//  SandBot
//
//  Created by Anderson Colburn on 4/19/26.
//


import SwiftUI

struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    var isDisabled: Bool = false
    var style: ButtonStyle = .gold

    enum ButtonStyle { case gold, secondary, destructive }

    var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(.sandButton)
                .foregroundColor(labelColor)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(background)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(borderColor, lineWidth: 1)
                )
                .cornerRadius(8)
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1.0)
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .gold:        RoundedRectangle(cornerRadius: 8).fill(Color.sandGold)
        case .secondary:   RoundedRectangle(cornerRadius: 8).fill(Color.clear)
        case .destructive: RoundedRectangle(cornerRadius: 8).fill(Color.clear)
        }
    }

    private var labelColor: Color {
        switch style {
        case .gold:        return Color.sandBgPrimary
        case .secondary:   return Color.sandGold
        case .destructive: return Color.sandOrange
        }
    }

    private var borderColor: Color {
        switch style {
        case .gold:        return Color.sandGold.opacity(0.3)
        case .secondary:   return Color.sandGold
        case .destructive: return Color.sandOrange
        }
    }
}
