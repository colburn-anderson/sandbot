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
    @Binding var layout: TextLayout

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
                Slider(value: $fontSize, in: 30...450, step: 5)
                    .tint(Color.sandGold)
            }

            // Curve
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("CURVE")
                        .font(.sandCaption)
                        .foregroundColor(.sandTextSecondary)
                    Spacer()
                    if layout.curve != 0 {
                        Button("Straighten") { layout.curve = 0 }
                            .font(.sandCaption)
                            .foregroundColor(.sandGold)
                            .buttonStyle(.borderless)
                    }
                }
                HStack(spacing: 10) {
                    Text("∪ Dip").font(.sandCaption).foregroundColor(.sandTextSecondary)
                    Slider(value: $layout.curve, in: -1...1, step: 0.05)
                        .tint(Color.sandGold)
                    Text("Arch ∩").font(.sandCaption).foregroundColor(.sandTextSecondary)
                }
            }

            // Rotation
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("ROTATION")
                        .font(.sandCaption)
                        .foregroundColor(.sandTextSecondary)
                    Spacer()
                    Text("\(Int(layout.rotation.rounded()))°")
                        .font(.sandCaption)
                        .foregroundColor(.sandGold)
                    if layout.rotation != 0 {
                        Button("Reset") { layout.rotation = 0 }
                            .font(.sandCaption)
                            .foregroundColor(.sandGold)
                            .buttonStyle(.borderless)
                    }
                }
                HStack(spacing: 10) {
                    Button("−90°") { layout.rotation = TextLayout.normalized(layout.rotation - 90) }
                        .font(.sandCaption).foregroundColor(.sandGold).buttonStyle(.borderless)
                    Slider(value: $layout.rotation, in: -180...180, step: 1)
                        .tint(Color.sandGold)
                    Button("+90°") { layout.rotation = TextLayout.normalized(layout.rotation + 90) }
                        .font(.sandCaption).foregroundColor(.sandGold).buttonStyle(.borderless)
                }
            }

            // Live preview — the real pit; drag the text to move it
            if !inputText.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    PitTextPreview(text: inputText, fontSize: fontSize, fontName: selectedFont, layout: $layout)
                    HStack {
                        Text("Drag to move · twist with two fingers to rotate")
                            .font(.sandCaption)
                            .foregroundColor(.sandTextSecondary)
                        Spacer()
                        if layout.centerX != nil {
                            Button("Re-center") {
                                layout.centerX = nil
                                layout.centerY = nil
                            }
                            .font(.sandCaption)
                            .foregroundColor(.sandGold)
                            .buttonStyle(.borderless)
                        }
                    }
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

/// What the robot will actually draw, drawn over the real pit outline.
/// The bridge returns the strokes in arm mm; dragging moves them instantly on
/// the phone, and the exact (rim-clipped) version is fetched on release.
/// Falls back to an on-device mockup when the robot is offline.
struct PitTextPreview: View {
    let text: String
    let fontSize: Double
    let fontName: String
    @Binding var layout: TextLayout

    @ObservedObject private var store = PitBoundaryStore.shared
    @State private var preview: TextPreviewStrokes? = nil
    @State private var isLoading = false
    @State private var dragMM: CGSize = .zero   // live drag offset in mm (x right, y away from base)
    @State private var liveAngle: Double = 0    // live two-finger twist, degrees counter-clockwise

    private var requestKey: String {
        "\(text)|\(Int(fontSize))|\(fontName)|\(layout.centerX ?? -999)|\(layout.centerY ?? -999)|\(layout.curve)|\(layout.rotation)"
    }

    var body: some View {
        let boundary = store.boundary
        let vp = boundary.viewport
        ZStack {
            PitBackdrop(boundary: boundary)
            if let preview {
                Canvas { context, size in
                    let rect = CGRect(origin: .zero, size: size)
                    let center = textCenter(vp)
                    let a = liveAngle * .pi / 180, cosA = cos(a), sinA = sin(a)
                    // Live twist about the text's centre, then live drag.
                    func place(_ pt: [Double]) -> CGPoint {
                        let dx = pt[0] - center.x, dy = pt[1] - center.y
                        return vp.point(x: center.x + dx * cosA - dy * sinA + dragMM.width,
                                        y: center.y + dx * sinA + dy * cosA + dragMM.height, in: rect)
                    }
                    func path(_ lines: [[[Double]]], closed: Bool) -> Path {
                        var p = Path()
                        for line in lines where line.count > 1 {
                            p.move(to: place(line[0]))
                            for pt in line.dropFirst() { p.addLine(to: place(pt)) }
                            if closed { p.closeSubpath() }
                        }
                        return p
                    }
                    // Everything, faintly (shows what gets clipped at the rim) …
                    context.stroke(path(preview.full, closed: true), with: .color(.sandTextSecondary.opacity(0.35)), lineWidth: 1)
                    // … and what will actually be drawn.
                    context.stroke(path(preview.strokes, closed: false), with: .color(.sandTextPrimary),
                                   style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            } else {
                Text(text)
                    .font(.custom(fontName, size: fontSize * 0.35))
                    .foregroundColor(.sandTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.3)
                    .padding(.horizontal, 24)
            }
            if isLoading {
                ProgressView().tint(Color.sandGold)
            }
        }
        .aspectRatio(boundary.aspectRatio, contentMode: .fit)
        .overlay(GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .highPriorityGesture(  // beat the Compose screen's scroll view
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            let mmPerPt = (vp.maxX - vp.minX) / max(geo.size.width, 1)
                            dragMM = CGSize(width: value.translation.width * mmPerPt,
                                            height: -value.translation.height * mmPerPt)
                        }
                        .onEnded { _ in commitDrag(viewport: vp) }
                        .simultaneously(with: RotationGesture()
                            // iOS angles are clockwise on screen; ours are counter-clockwise.
                            .onChanged { angle in liveAngle = -angle.degrees }
                            .onEnded { _ in commitRotation(viewport: vp) })
                )
        })
        .cornerRadius(8)
        .task(id: requestKey) {
            try? await Task.sleep(nanoseconds: 300_000_000)  // debounce typing / sliders
            guard !Task.isCancelled else { return }
            isLoading = true
            let fresh = try? await RobotService.shared.fetchTextPreview(
                text, fontSize: Int(fontSize), fontName: fontName, layout: layout)
            if !Task.isCancelled {
                if let fresh { preview = fresh }
                isLoading = false
            }
        }
    }

    /// Middle of the text in arm mm (where the bridge centres and rotates it).
    private func textCenter(_ vp: PitViewport) -> (x: Double, y: Double) {
        (layout.centerX ?? (vp.minX + vp.maxX) / 2, layout.centerY ?? (vp.minY + vp.maxY) / 2)
    }

    /// Bake a two-finger twist into the layout, rotating what's on screen
    /// right away; the layout change then fetches the exact preview.
    private func commitRotation(viewport vp: PitViewport) {
        guard liveAngle != 0 else { return }
        let c = textCenter(vp)
        let a = liveAngle * .pi / 180, cosA = cos(a), sinA = sin(a)
        if let p = preview {
            let turn: ([[[Double]]]) -> [[[Double]]] = {
                $0.map { $0.map { pt in
                    let dx = pt[0] - c.x, dy = pt[1] - c.y
                    return [c.x + dx * cosA - dy * sinA, c.y + dx * sinA + dy * cosA]
                } }
            }
            preview = TextPreviewStrokes(strokes: turn(p.strokes), full: turn(p.full))
        }
        layout.rotation = TextLayout.normalized(layout.rotation + liveAngle)
        liveAngle = 0
    }

    /// Bake the drag into the layout: shift what's on screen right away (no
    /// flicker), then the layout change triggers a fresh, exact preview.
    private func commitDrag(viewport vp: PitViewport) {
        guard dragMM != .zero else { return }
        let dx = Double(dragMM.width), dy = Double(dragMM.height)
        layout.centerX = (layout.centerX ?? (vp.minX + vp.maxX) / 2) + dx
        layout.centerY = (layout.centerY ?? (vp.minY + vp.maxY) / 2) + dy
        if let p = preview {
            let shift: ([[[Double]]]) -> [[[Double]]] = { $0.map { $0.map { [$0[0] + dx, $0[1] + dy] } } }
            preview = TextPreviewStrokes(strokes: shift(p.strokes), full: shift(p.full))
        }
        dragMM = .zero
    }
}
