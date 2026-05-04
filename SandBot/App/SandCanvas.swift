//
//  SandCanvas.swift
//  SandBot
//
//  Created by Anderson Colburn on 4/19/26.
//

import SwiftUI

struct SandCanvas: View {
    let strokes: [Stroke]
    
    @State private var flatPoints: [(StrokePoint, CGFloat)] = []
    @State private var totalLength: CGFloat = 0

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
        
        // Calculate total arc length across all strokes
        var totalLength: CGFloat = 0
        for stroke in strokes {
            for i in 1..<stroke.count {
                let dx = stroke[i].x - stroke[i-1].x
                let dy = stroke[i].y - stroke[i-1].y
                totalLength += sqrt(dx*dx + dy*dy)
            }
        }
        
        guard totalLength > 0 else { return }
        
        // Build a flat list of (point, cumulative distance) pairs
        var flatPoints: [(StrokePoint, CGFloat)] = []
        var cumulative: CGFloat = 0
        
        for stroke in strokes {
            for i in 0..<stroke.count {
                if i == 0 {
                    flatPoints.append((stroke[i], cumulative))
                } else {
                    let dx = stroke[i].x - stroke[i-1].x
                    let dy = stroke[i].y - stroke[i-1].y
                    cumulative += sqrt(dx*dx + dy*dy)
                    flatPoints.append((stroke[i], cumulative))
                }
            }
        }
        
        await MainActor.run { self.flatPoints = flatPoints }
        await MainActor.run { self.totalLength = totalLength }
        
        let totalDuration = 10.0
        let steps = 200
        let stepDuration = totalDuration / Double(steps)
        
        for i in 1...steps {
            if Task.isCancelled { break }
            await MainActor.run {
                progress = CGFloat(i) / CGFloat(steps)
            }
            try? await Task.sleep(nanoseconds: UInt64(stepDuration * 1_000_000_000))
        }
        await MainActor.run { progress = 1.0 }
    }

    private func drawStrokes(context: GraphicsContext, size: CGSize, progress: CGFloat) {
        guard !flatPoints.isEmpty, totalLength > 0 else {
            // Fallback — draw everything instantly
            for stroke in strokes {
                guard stroke.count > 1 else { continue }
                var path = Path()
                path.move(to: CGPoint(x: stroke[0].x * size.width, y: stroke[0].y * size.height))
                for point in stroke.dropFirst() {
                    path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
                }
                context.stroke(path, with: .color(Color.sandGold),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
            return
        }
        
        let distanceToDraw = totalLength * progress
        var lastPoint: CGPoint? = nil
        
        // Group flat points back into strokes for drawing
        var strokeIndex = 0
        var pointIndex = 0
        var currentPath = Path()
        var pathStarted = false
        var lastStrokeSize = 0
        
        for stroke in strokes {
            if pointIndex >= flatPoints.count { break }
            
            var strokePath = Path()
            var strokeStarted = false
            
            for _ in 0..<stroke.count {
                if pointIndex >= flatPoints.count { break }
                let (point, dist) = flatPoints[pointIndex]
                if dist > distanceToDraw { break }
                
                let cp = CGPoint(x: point.x * size.width, y: point.y * size.height)
                
                if !strokeStarted {
                    strokePath.move(to: cp)
                    strokeStarted = true
                } else {
                    strokePath.addLine(to: cp)
                }
                lastPoint = cp
                pointIndex += 1
            }
            
            if strokeStarted {
                context.stroke(strokePath, with: .color(Color.sandGold),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
            
            strokeIndex += 1
        }
        
        // Cursor dot
        if let lp = lastPoint, progress > 0 && progress < 1 {
            var dot = Path()
            dot.addEllipse(in: CGRect(x: lp.x - 3, y: lp.y - 3, width: 6, height: 6))
            context.fill(dot, with: .color(Color.sandGold))
        }
    }
}
