//
//  TextDrawView.swift
//  SandBot
//
//  Restored font picker with all original custom fonts.
//  Text is sent to the bridge for drawing, but the font preview
//  still renders on-device for instant visual feedback.
//

import SwiftUI

struct TextDrawView: View {
    @Binding var inputText: String
    @Binding var fontSize: Double
    @Binding var selectedFont: String

    let availableFonts: [(name: String, displayName: String)] = [
        ("Helvetica-Bold", "Helvetica"),
        ("Georgia-Bold", "Georgia"),
        ("Courier-Bold", "Courier"),
        ("AvenirNext-Heavy", "Avenir"),
        ("Futura-Bold", "Futura"),
        ("AmericanTypewriter-Bold", "Typewriter"),
        ("Baskerville-Bold", "Baskerville"),
        ("GillSans-Bold", "Gill Sans"),
        ("DancingScript-Bold", "Dancing"),
        ("Parisienne-Regular", "Parisienne"),
        ("Rochester-Regular", "Rochester"),
        ("Sacramento-Regular", "Sacramento"),
        ("PetitFormalScript-Regular", "Petit Formal"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Text input
            VStack(alignment: .leading, spacing: 8) {
                Text("MESSAGE")
                    .font(.sandCaption)
                    .foregroundColor(.sandTextSecondary)
                TextField("Type something...", text: $inputText)
                    .font(.sandBody)
                    .foregroundColor(.sandTextPrimary)
                    .padding(12)
                    .background(Color.sandSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.sandBorder, lineWidth: 1)
                    )
                    .cornerRadius(8)
            }

            // Font picker
            VStack(alignment: .leading, spacing: 8) {
                Text("FONT")
                    .font(.sandCaption)
                    .foregroundColor(.sandTextSecondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(availableFonts, id: \.name) { font in
                            FontChip(
                                fontName: font.name,
                                displayName: font.displayName,
                                previewText: inputText.isEmpty ? "Abc" : inputText,
                                isSelected: selectedFont == font.name
                            )
                            .onTapGesture {
                                selectedFont = font.name
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .mask(
                    HStack(spacing: 0) {
                        Rectangle().fill(Color.black)
                        LinearGradient(
                            gradient: Gradient(colors: [.black, .clear]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 40)
                    }
                )
            }

            // Font size slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("SIZE")
                        .font(.sandCaption)
                        .foregroundColor(.sandTextSecondary)
                    Spacer()
                    Text("\(Int(fontSize))pt")
                        .font(.sandCaption)
                        .foregroundColor(.sandGold)
                }
                Slider(value: $fontSize, in: 30...150, step: 5)
                    .tint(Color.sandGold)
            }

            // Live preview
            if !inputText.isEmpty {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.sandSurface)
                        .frame(height: 120)

                    Text(inputText)
                        .font(.custom(selectedFont, size: fontSize * 0.35))
                        .foregroundColor(.sandTextPrimary)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
        }
        .padding(.horizontal)
        .padding(.top)
        .padding(.bottom, 8)
    }
}

struct FontChip: View {
    let fontName: String
    let displayName: String
    let previewText: String
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text(previewText.prefix(8).description)
                .font(.custom(fontName, size: 18))
                .foregroundColor(isSelected ? Color.sandBgPrimary : Color.sandTextPrimary)
                .lineLimit(1)
            Text(displayName)
                .font(.sandCaption)
                .foregroundColor(isSelected ? Color.sandBgPrimary : Color.sandTextSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isSelected ? Color.sandGold : Color.sandSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.sandGold : Color.sandBorder, lineWidth: 1)
        )
        .cornerRadius(8)
    }
}
