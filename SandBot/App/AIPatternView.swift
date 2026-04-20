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

    @State private var description: String = ""
    @State private var isGenerating: Bool = false
    @State private var errorMessage: String? = nil

    let presets: [(label: String, prompt: String)] = [
        ("Spiral Galaxy", "A dense spiral galaxy with multiple arms curving outward from the center, filled with many fine curved lines"),
        ("Mandala", "A detailed circular mandala with repeating geometric patterns radiating from the center, 8-fold symmetry"),
        ("Wave Field", "A field of overlapping sine waves at different frequencies and phases, covering the entire surface"),
        ("Celtic Knot", "An intricate Celtic knot pattern with interwoven continuous lines forming a complex knotwork"),
        ("Hexagon Grid", "A dense grid of hexagons covering the entire surface, each hexagon outlined precisely"),
        ("Fibonacci Sunflower", "A sunflower fibonacci spiral pattern with seeds arranged in golden ratio spirals"),
        ("Lissajous", "A complex lissajous figure with frequency ratio 3:4, drawn as a single continuous looping path"),
        ("Radial Burst", "Many lines radiating outward from the center at equal angles, with concentric circles crossing them"),
        ("Maze", "A dense rectangular maze filling the entire surface with many corridors and dead ends"),
        ("Rose Curve", "A mathematical rose curve with 8 petals, drawn with fine detail and multiple overlapping passes"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Preset chips
            VStack(alignment: .leading, spacing: 8) {
                Text("PRESETS")
                    .font(.sandCaption)
                    .foregroundColor(.sandTextSecondary)
                    .padding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(presets, id: \.label) { preset in
                            Button(action: {
                                description = preset.prompt
                                inputLabel = preset.label
                            }) {
                                Text(preset.label)
                                    .font(.sandCaption)
                                    .foregroundColor(description == preset.prompt ? Color.sandBgPrimary : Color.sandTextPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(description == preset.prompt ? Color.sandGold : Color.sandSurface)
                                    .overlay(
                                        Capsule()
                                            .stroke(description == preset.prompt ? Color.sandGold : Color.sandBorder, lineWidth: 1)
                                    )
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }

            // Custom description
            VStack(alignment: .leading, spacing: 8) {
                Text("DESCRIPTION")
                    .font(.sandCaption)
                    .foregroundColor(.sandTextSecondary)

                ZStack(alignment: .topLeading) {
                    if description.isEmpty {
                        Text("Describe a pattern...")
                            .font(.sandBody)
                            .foregroundColor(.sandTextSecondary)
                            .padding(12)
                    }
                    TextEditor(text: $description)
                        .font(.sandBody)
                        .foregroundColor(.sandTextPrimary)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 100)
                        .onChange(of: description) {
                            if !presets.map(\.prompt).contains(description) {
                                inputLabel = description
                            }
                        }
                }
                .background(Color.sandSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.sandBorder, lineWidth: 1)
                )
                .cornerRadius(8)
            }
            .padding(.horizontal)

            // Error
            if let error = errorMessage {
                Text(error)
                    .font(.sandCaption)
                    .foregroundColor(.sandError)
                    .padding(.horizontal)
            }

            // Generate button
            PrimaryButton(
                title: isGenerating ? "Generating..." : "Generate Pattern",
                action: generatePattern,
                isDisabled: description.trimmingCharacters(in: .whitespaces).isEmpty || isGenerating
            )
            .padding(.horizontal)
        }
        .padding(.vertical)
    }

    private func generatePattern() {
        errorMessage = nil
        isGenerating = true
        strokes = []

        Task {
            do {
                let result = try await ClaudeService.shared.generatePattern(description: description)
                await MainActor.run {
                    strokes = result
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isGenerating = false
                }
            }
        }
    }
}
