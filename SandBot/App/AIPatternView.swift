//
//  AIPatternView.swift
//  SandBot
//
//  Created by Anderson Colburn on 4/19/26.
//

import SwiftUI

struct AIPatternView: View {
    @Binding var strokes: [Stroke]
    @Binding var inputLabel: String

    @State private var selectedPattern: String? = nil
    @State private var density: Double = 0.4
    @State private var distortion: Double = 0.0

    private let generator = PatternGenerator.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // Pattern presets
            VStack(alignment: .leading, spacing: 10) {
                Text("PATTERNS")
                    .font(.sandCaption)
                    .foregroundColor(.sandTextSecondary)
                    .padding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(generator.allPatterns, id: \.label) { pattern in
                            Button(action: {
                                selectedPattern = pattern.label
                                inputLabel = pattern.label
                                regenerate(pattern: pattern)
                            }) {
                                VStack(spacing: 4) {
                                    Text(pattern.label)
                                        .font(.sandBody)
                                        .foregroundColor(selectedPattern == pattern.label ? Color.sandBgPrimary : Color.sandTextPrimary)
                                    Text(pattern.description)
                                        .font(.sandCaption)
                                        .foregroundColor(selectedPattern == pattern.label ? Color.sandBgPrimary.opacity(0.7) : Color.sandTextSecondary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(selectedPattern == pattern.label ? Color.sandGold : Color.sandSurface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(selectedPattern == pattern.label ? Color.sandGold : Color.sandBorder, lineWidth: 1)
                                )
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }

            // Sliders — only show when a math pattern is selected
            if selectedPattern != nil {
                VStack(spacing: 14) {
                    SliderRow(
                        label: "DENSITY",
                        value: $density,
                        leftLabel: "Sparse",
                        rightLabel: "Dense",
                        range: 0.0...0.9
                    )
                    SliderRow(
                        label: "DISTORTION",
                        value: $distortion,
                        leftLabel: "Pure",
                        rightLabel: "Organic"
                    )
                }
                .padding(.horizontal)
                .onChange(of: density) { regenerateSelected() }
                .onChange(of: distortion) { regenerateSelected() }
            }

        }
        .padding(.vertical)
    }

    private func regenerate(pattern: PatternGenerator.Pattern) {
        strokes = pattern.generate(density, distortion)
    }

    private func regenerateSelected() {
        guard let label = selectedPattern,
              let pattern = generator.allPatterns.first(where: { $0.label == label }) else { return }
        strokes = pattern.generate(density, distortion)
    }

}

struct SliderRow: View {
    let label: String
    @Binding var value: Double
    let leftLabel: String
    let rightLabel: String
    var range: ClosedRange<Double> = 0...1

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.sandCaption)
                .foregroundColor(.sandTextSecondary)
            HStack(spacing: 10) {
                Text(leftLabel)
                    .font(.sandCaption)
                    .foregroundColor(.sandTextSecondary)
                Slider(value: $value, in: range)
                    .tint(Color.sandGold)
                Text(rightLabel)
                    .font(.sandCaption)
                    .foregroundColor(.sandTextSecondary)
            }
        }
    }
}
