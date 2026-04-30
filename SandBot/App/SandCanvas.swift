//
//  SandCanvas.swift
//  SandBot
//
//  Created by Anderson Colburn on 4/19/26.
//

import SwiftUI

struct SandCanvas: View {
    let strokes: [Stroke]

    @State private var progress: CGFloat = 1.0
    @State private var debounceTask: Task<Void, Never>? = nil

    var body: some View {
        Canvas { context, size in
            drawStrokes(context: context, size: size, progress: progress)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(16/9, contentMode: .fit)
        .background(Color.sandBgSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.sandGold.opacity(0.25), lineWidth: 1)
        )
        .cornerRadius(12)
        .padding(.horizontal, 8)
        .onChange(of: strokes) {
            debounceTask?.cancel()
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: 600_000_000)
                if !Task.isCancelled {
                    await animate()
                }
            }
        }
        .onAppear {
            if !strokes.isEmpty {
                progress = 1.0
            }
        }
    }

    private func animate() async {
        await MainActor.run { progress = 0 }

        let totalPoints = strokes.reduce(0) { $0 + $1.count }
        guard totalPoints > 0 else { return }

        // Fixed 10 second animation
        let totalSteps = 200
        let stepDuration = 10.0 / Double(totalSteps)

        for i in 1...totalSteps {
            if Task.isCancelled { break }
            await MainActor.run {
                progress = CGFloat(i) / CGFloat(totalSteps)
            }
            try? await Task.sleep(nanoseconds: UInt64(stepDuration * 1_000_000_000))
        }
        await MainActor.run { progress = 1.0 }
    }

    private func drawStrokes(context: GraphicsContext, size: CGSize, progress: CGFloat) {
        guard !strokes.isEmpty else { return }

        let totalPoints = strokes.reduce(0) { $0 + $1.count }
        guard totalPoints > 0 else { return }

        let pointsToDraw = Int(CGFloat(totalPoints) * progress)
        var pointsDrawn = 0
        var lastPoint: CGPoint? = nil

        for stroke in strokes {
            guard stroke.count > 1 else { continue }
            if pointsDrawn >= pointsToDraw { break }

            let remainingPoints = pointsToDraw - pointsDrawn
            let pointsInStroke = min(stroke.count, remainingPoints)

            var path = Path()
            path.move(to: CGPoint(
                x: stroke[0].x * size.width,
                y: stroke[0].y * size.height
            ))

            for i in 1..<pointsInStroke {
                let cp = CGPoint(
                    x: stroke[i].x * size.width,
                    y: stroke[i].y * size.height
                )
                path.addLine(to: cp)
                lastPoint = cp
            }

            context.stroke(path, with: .color(Color.sandGold),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

            pointsDrawn += pointsInStroke
        }

        // Simple cursor dot
        if let lp = lastPoint, progress > 0 && progress < 1 {
            var dot = Path()
            dot.addEllipse(in: CGRect(x: lp.x - 3, y: lp.y - 3, width: 6, height: 6))
            context.fill(dot, with: .color(Color.sandGold))
        }
    }
}
