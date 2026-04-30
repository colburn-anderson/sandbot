//
//  SandCanvas.swift
//  SandBot
//
//  Created by Anderson Colburn on 4/19/26.
//

import SwiftUI

struct SandCanvas: View {
    let strokes: [Stroke]
    var animated: Bool = true

    @State private var progress: CGFloat = 0
    @State private var animationTask: Task<Void, Never>? = nil

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
            if animated {
                startAnimation()
            } else {
                progress = 1.0
            }
        }
        .onAppear {
            if !strokes.isEmpty {
                if animated {
                    startAnimation()
                } else {
                    progress = 1.0
                }
            }
        }
    }

    private func drawStrokes(context: GraphicsContext, size: CGSize, progress: CGFloat) {
        guard !strokes.isEmpty else { return }

        // Calculate total points across all strokes
        let totalPoints = strokes.reduce(0) { $0 + $1.count }
        guard totalPoints > 0 else { return }

        let pointsToDraw = Int(CGFloat(totalPoints) * progress)
        var pointsDrawn = 0

        for stroke in strokes {
            guard stroke.count > 1 else { continue }
            if pointsDrawn >= pointsToDraw { break }

            var path = Path()
            var startedPath = false

            for point in stroke {
                if pointsDrawn >= pointsToDraw { break }

                let x = point.x * size.width
                let y = point.y * size.height
                let cgPoint = CGPoint(x: x, y: y)

                if !startedPath {
                    path.move(to: cgPoint)
                    startedPath = true
                } else {
                    path.addLine(to: cgPoint)
                }
                pointsDrawn += 1
            }

            if startedPath {
                context.stroke(
                    path,
                    with: .color(Color.sandGold),
                    style: StrokeStyle(
                        lineWidth: 1.5,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }
        }

        // Draw cursor dot at current position
        if progress > 0 && progress < 1 {
            var currentPoint: CGPoint? = nil
            var drawn = 0
            outer: for stroke in strokes {
                for point in stroke {
                    if drawn >= pointsToDraw { break outer }
                    currentPoint = CGPoint(
                        x: point.x * size.width,
                        y: point.y * size.height
                    )
                    drawn += 1
                }
            }
            if let cp = currentPoint {
                var dotPath = Path()
                dotPath.addEllipse(in: CGRect(
                    x: cp.x - 3,
                    y: cp.y - 3,
                    width: 6,
                    height: 6
                ))
                context.fill(dotPath, with: .color(Color.sandGold))
            }
        }
    }

    private func startAnimation() {
        animationTask?.cancel()
        progress = 0

        // Calculate duration based on number of points
        let totalPoints = strokes.reduce(0) { $0 + $1.count }
        let duration = min(max(Double(totalPoints) / 500.0, 1.0), 6.0)

        animationTask = Task {
            let steps = 120
            let stepDuration = duration / Double(steps)

            for i in 0...steps {
                if Task.isCancelled { break }
                let newProgress = CGFloat(i) / CGFloat(steps)
                await MainActor.run {
                    withAnimation(.linear(duration: stepDuration)) {
                        progress = newProgress
                    }
                }
                try? await Task.sleep(nanoseconds: UInt64(stepDuration * 1_000_000_000))
            }

            await MainActor.run { progress = 1.0 }
        }
    }
}
