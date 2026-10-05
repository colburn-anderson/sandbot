//
//  PitLayoutPreview.swift
//  SandBot
//
//  Shared by text and image drawings: a preview of exactly what the robot
//  will draw over the real pit outline, plus the controls that place it
//  (drag, two-finger twist, curve, rotation, size).
//

import SwiftUI

/// What the robot will actually draw, drawn over the real pit outline.
/// The bridge returns the strokes in arm mm; dragging and twisting move them
/// instantly on the phone, and the exact (rim-clipped) version is fetched on
/// release. Shows `fallback` until the robot has answered (e.g. offline).
struct PitLayoutPreview<Fallback: View>: View {
    /// Changes whenever the content changes (text, font, image, filters).
    let requestKey: String
    @Binding var layout: DrawingLayout
    let fetch: (DrawingLayout) async throws -> PreviewStrokes
    @ViewBuilder let fallback: () -> Fallback

    @ObservedObject private var store = PitBoundaryStore.shared
    @State private var preview: PreviewStrokes? = nil
    @State private var isLoading = false
    @State private var dragMM: CGSize = .zero   // live drag offset in mm (x right, y away from base)
    @State private var liveAngle: Double = 0    // live two-finger twist, degrees counter-clockwise

    private var fullKey: String {
        "\(requestKey)|\(layout.centerX ?? -999)|\(layout.centerY ?? -999)|\(layout.curve)|\(layout.rotation)|\(layout.scale)"
    }

    var body: some View {
        let boundary = store.boundary
        let vp = boundary.viewport
        ZStack {
            PitBackdrop(boundary: boundary)
            if let preview {
                Canvas { context, size in
                    let rect = CGRect(origin: .zero, size: size)
                    let center = drawingCenter(vp)
                    let a = liveAngle * .pi / 180, cosA = cos(a), sinA = sin(a)
                    // Live twist about the drawing's centre, then live drag.
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
                fallback()
            }
            if isLoading {
                ProgressView().tint(Color.sandGold)
            }
            if let preview, let count = preview.strokeCount, let minutes = preview.minutes {
                VStack {
                    Spacer()
                    HStack {
                        Text(preview.isTooLong
                             ? "Too detailed: ~\(Int(minutes.rounded())) min. Lower threshold or simplify"
                             : "\(count) strokes · about \(max(1, Int(minutes.rounded()))) min")
                            .font(.sandCaption)
                            .foregroundColor(preview.isTooLong ? .sandError : .sandTextSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.sandBgPrimary.opacity(0.7))
                            .cornerRadius(4)
                        Spacer()
                    }
                }
                .padding(6)
                .allowsHitTesting(false)
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
        .onChange(of: requestKey) { preview = nil }  // new content: don't show the old drawing
        .task(id: fullKey) {
            try? await Task.sleep(nanoseconds: 300_000_000)  // debounce typing / sliders
            guard !Task.isCancelled else { return }
            isLoading = true
            let fresh = try? await fetch(layout)
            if !Task.isCancelled {
                if let fresh { preview = fresh }
                isLoading = false
            }
        }
    }

    /// Middle of the drawing in arm mm (where the bridge centres and rotates it).
    private func drawingCenter(_ vp: PitViewport) -> (x: Double, y: Double) {
        (layout.centerX ?? (vp.minX + vp.maxX) / 2, layout.centerY ?? (vp.minY + vp.maxY) / 2)
    }

    /// Bake a two-finger twist into the layout, rotating what's on screen
    /// right away; the layout change then fetches the exact preview.
    private func commitRotation(viewport vp: PitViewport) {
        guard liveAngle != 0 else { return }
        let c = drawingCenter(vp)
        let a = liveAngle * .pi / 180, cosA = cos(a), sinA = sin(a)
        if let p = preview {
            let turn: ([[[Double]]]) -> [[[Double]]] = {
                $0.map { $0.map { pt in
                    let dx = pt[0] - c.x, dy = pt[1] - c.y
                    return [c.x + dx * cosA - dy * sinA, c.y + dx * sinA + dy * cosA]
                } }
            }
            var q = p
            q.strokes = turn(p.strokes)
            q.full = turn(p.full)
            preview = q
        }
        layout.rotation = DrawingLayout.normalized(layout.rotation + liveAngle)
        liveAngle = 0
    }

    /// Bake the drag into the layout: shift what's on screen right away (no
    /// flicker), then the layout change triggers a fresh, exact preview.
    private func commitDrag(viewport vp: PitViewport) {
        guard dragMM != .zero else { return }
        let dx = Double(dragMM.width), dy = Double(dragMM.height)
        let c = drawingCenter(vp)
        layout.centerX = c.x + dx
        layout.centerY = c.y + dy
        if let p = preview {
            let shift: ([[[Double]]]) -> [[[Double]]] = { $0.map { $0.map { [$0[0] + dx, $0[1] + dy] } } }
            var q = p
            q.strokes = shift(p.strokes)
            q.full = shift(p.full)
            preview = q
        }
        dragMM = .zero
    }
}

/// "Drag to move" hint under a preview, with a Re-center button once moved.
struct PreviewHint: View {
    @Binding var layout: DrawingLayout

    var body: some View {
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

/// Curve and rotation sliders (and size, for images).
struct LayoutControls: View {
    @Binding var layout: DrawingLayout
    var showsScale = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsScale {
                VStack(alignment: .leading, spacing: 4) {
                    header("SIZE", value: "\(Int((layout.scale * 100).rounded()))%",
                           reset: layout.scale != 1 ? { layout.scale = 1 } : nil)
                    Slider(value: $layout.scale, in: 0.2...1.5, step: 0.05)
                        .tint(Color.sandGold)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                header("CURVE", value: nil,
                       reset: layout.curve != 0 ? { layout.curve = 0 } : nil, resetTitle: "Straighten")
                HStack(spacing: 10) {
                    Text("∪ Dip").font(.sandCaption).foregroundColor(.sandTextSecondary)
                    Slider(value: $layout.curve, in: -1...1, step: 0.05)
                        .tint(Color.sandGold)
                    Text("Arch ∩").font(.sandCaption).foregroundColor(.sandTextSecondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                header("ROTATION", value: "\(Int(layout.rotation.rounded()))°",
                       reset: layout.rotation != 0 ? { layout.rotation = 0 } : nil)
                HStack(spacing: 10) {
                    Button("−90°") { layout.rotation = DrawingLayout.normalized(layout.rotation - 90) }
                        .font(.sandCaption).foregroundColor(.sandGold).buttonStyle(.borderless)
                    Slider(value: $layout.rotation, in: -180...180, step: 1)
                        .tint(Color.sandGold)
                    Button("+90°") { layout.rotation = DrawingLayout.normalized(layout.rotation + 90) }
                        .font(.sandCaption).foregroundColor(.sandGold).buttonStyle(.borderless)
                }
            }
        }
    }

    private func header(_ title: String, value: String?, reset: (() -> Void)?, resetTitle: String = "Reset") -> some View {
        HStack {
            Text(title)
                .font(.sandCaption)
                .foregroundColor(.sandTextSecondary)
            Spacer()
            if let value {
                Text(value)
                    .font(.sandCaption)
                    .foregroundColor(.sandGold)
            }
            if let reset {
                Button(resetTitle, action: reset)
                    .font(.sandCaption)
                    .foregroundColor(.sandGold)
                    .buttonStyle(.borderless)
            }
        }
    }
}
