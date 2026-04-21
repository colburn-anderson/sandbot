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

    @State private var customDescription: String = ""
    @State private var isGenerating: Bool = false
    @State private var errorMessage: String? = nil
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
                                customDescription = ""
                                errorMessage = nil
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

            // Divider
            HStack {
                Rectangle().fill(Color.sandBorder).frame(height: 1)
                Text("OR").font(.sandCaption).foregroundColor(.sandTextSecondary).padding(.horizontal, 8)
                Rectangle().fill(Color.sandBorder).frame(height: 1)
            }
            .padding(.horizontal)

            // Custom AI
            VStack(alignment: .leading, spacing: 8) {
                Text("CUSTOM (AI)")
                    .font(.sandCaption)
                    .foregroundColor(.sandTextSecondary)

                ZStack(alignment: .topLeading) {
                    if customDescription.isEmpty {
                        Text("Describe something unique...")
                            .font(.sandBody)
                            .foregroundColor(.sandTextSecondary)
                            .padding(12)
                    }
                    TextEditor(text: $customDescription)
                        .font(.sandBody)
                        .foregroundColor(.sandTextPrimary)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 80)
                        .onChange(of: customDescription) {
                            if !customDescription.isEmpty {
                                selectedPattern = nil
                                inputLabel = customDescription
                            }
                        }
                }
                .background(Color.sandSurface)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.sandBorder, lineWidth: 1))
                .cornerRadius(8)
            }
            .padding(.horizontal)

            if let error = errorMessage {
                Text(error).font(.sandCaption).foregroundColor(.sandError).padding(.horizontal)
            }

            if !customDescription.trimmingCharacters(in: .whitespaces).isEmpty {
                PrimaryButton(
                    title: isGenerating ? "Generating..." : "Generate with AI",
                    action: generateWithClaude,
                    isDisabled: isGenerating
                )
                .padding(.horizontal)
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

    private func generateWithClaude() {
        errorMessage = nil
        isGenerating = true
        strokes = []
        Task {
            do {
                let result = try await ClaudeService.shared.generatePattern(description: customDescription)
                await MainActor.run { strokes = result; isGenerating = false }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription; isGenerating = false }
            }
        }
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
