//
//  PatternGenerator.swift
//  SandBot
//
//  Created by Anderson Colburn on 4/20/26.
//


import Foundation

final class PatternGenerator {
    static let shared = PatternGenerator()

    struct Pattern {
        let label: String
        let description: String
        let generate: (_ density: Double, _ distortion: Double) -> [Stroke]
    }

    lazy var allPatterns: [Pattern] = [
        Pattern(label: "Archimedes Spiral", description: "Classic expanding spiral",    generate: archimedesSpiral),
        Pattern(label: "Double Spiral",     description: "Two interleaved spirals",     generate: doubleSpiral),
        Pattern(label: "Triple Spiral",     description: "Three interleaved spirals",   generate: tripleSpiral),
        Pattern(label: "Sine Wave Field",   description: "Overlapping sine waves",      generate: sineWaveField),
        Pattern(label: "Concentric Circles",description: "Evenly spaced rings",         generate: concentricCircles),
        Pattern(label: "Radial Burst",      description: "Lines from center out",       generate: radialBurst),
        Pattern(label: "Lissajous 3:4",     description: "Classic lissajous curve",     generate: lissajous34),
        Pattern(label: "Rose Curve",        description: "8-petal rose",                generate: roseCurve),
        Pattern(label: "Hex Grid",          description: "Honeycomb grid",              generate: hexGrid),
        Pattern(label: "Fibonacci Spiral",  description: "Golden ratio spiral",         generate: fibonacciSpiral),
        Pattern(label: "Celtic Weave",      description: "Interlocking wave bands",     generate: celticWeave),
        Pattern(label: "Triquetra",         description: "Celtic trinity knot",         generate: triquetra),
        Pattern(label: "Shield Knot",       description: "Celtic shield knot",          generate: shieldKnot),
        Pattern(label: "Sunburst",          description: "Radiating arcs",              generate: sunburst),
        Pattern(label: "Ripple",            description: "Concentric ripple rings",     generate: ripple),
    ]

    // MARK: - Helpers
    private let cx = 0.5, cy = 0.5

    private func pt(_ x: Double, _ y: Double, z: Double = 0.5) -> StrokePoint {
        StrokePoint(x: max(0, min(1, x)), y: max(0, min(1, y)), z: z)
    }

    private func polarPt(r: Double, theta: Double, z: Double = 0.5) -> StrokePoint {
        pt(cx + r * cos(theta), cy + r * sin(theta), z: z)
    }

    private func wobble(_ val: Double, distortion: Double, freq: Double = 8, phase: Double = 0) -> Double {
        val + distortion * 0.03 * sin(freq * phase)
    }

    private func stepsFor(density: Double, min: Int = 100, max: Int = 400) -> Int {
        min + Int(density * Double(max - min))
    }

    // MARK: - Patterns

    func archimedesSpiral(density: Double, distortion: Double) -> [Stroke] {
        let turns = 3.0 + density * 10.0
        let steps = stepsFor(density: density)
        var stroke: Stroke = []
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let theta = t * turns * 2 * .pi
            let r = wobble(t * 0.46, distortion: distortion, freq: 12, phase: theta)
            stroke.append(polarPt(r: r, theta: theta))
        }
        return [stroke]
    }

    func doubleSpiral(density: Double, distortion: Double) -> [Stroke] {
        let turns = 3.0 + density * 10.0
        let steps = stepsFor(density: density)
        var s1: Stroke = [], s2: Stroke = []
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let theta = t * turns * 2 * .pi
            let r = wobble(t * 0.46, distortion: distortion, freq: 10, phase: theta)
            s1.append(polarPt(r: r, theta: theta))
            s2.append(polarPt(r: r, theta: theta + .pi))
        }
        return [s1, s2]
    }

    func tripleSpiral(density: Double, distortion: Double) -> [Stroke] {
        let turns = 3.0 + density * 10.0
        let steps = stepsFor(density: density)
        var strokes: [Stroke] = []
        for arm in 0..<3 {
            var stroke: Stroke = []
            let phase = Double(arm) / 3.0 * 2 * .pi
            for i in 0...steps {
                let t = Double(i) / Double(steps)
                let theta = t * turns * 2 * .pi + phase
                let r = wobble(t * 0.46, distortion: distortion, freq: 10, phase: theta)
                stroke.append(polarPt(r: r, theta: theta))
            }
            strokes.append(stroke)
        }
        return strokes
    }

    func sineWaveField(density: Double, distortion: Double) -> [Stroke] {
        let lineCount = 5 + Int(density * 30)
        var strokes: [Stroke] = []
        for i in 0..<lineCount {
            let y0 = Double(i) / Double(lineCount - 1)
            var stroke: Stroke = []
            let waveSteps = 200
            let freq = 2.0 + density * 5.0
            let amp = 0.02 + distortion * 0.06
            for j in 0...waveSteps {
                let x = Double(j) / Double(waveSteps)
                let phase = Double(i) * 0.4
                let y = y0 + amp * sin(freq * 2 * .pi * x + phase)
                stroke.append(pt(x, y))
            }
            strokes.append(stroke)
        }
        return strokes
    }

    func concentricCircles(density: Double, distortion: Double) -> [Stroke] {
        let ringCount = 3 + Int(density * 20)
        var strokes: [Stroke] = []
        for i in 1...ringCount {
            let r = Double(i) / Double(ringCount) * 0.46
            var stroke: Stroke = []
            let steps = 200
            for j in 0...steps {
                let theta = Double(j) / Double(steps) * 2 * .pi
                let rWobbled = wobble(r, distortion: distortion, freq: 6, phase: theta)
                stroke.append(polarPt(r: rWobbled, theta: theta))
            }
            strokes.append(stroke)
        }
        return strokes
    }

    func radialBurst(density: Double, distortion: Double) -> [Stroke] {
        let lineCount = 8 + Int(density * 60)
        var strokes: [Stroke] = []
        for i in 0..<lineCount {
            let theta = Double(i) / Double(lineCount) * 2 * .pi
            var stroke: Stroke = []
            for j in 0...40 {
                let t = Double(j) / 40.0
                let r = wobble(t * 0.47, distortion: distortion, freq: 5, phase: t * .pi)
                stroke.append(polarPt(r: r, theta: theta))
            }
            strokes.append(stroke)
        }
        return strokes
    }

    func lissajous34(density: Double, distortion: Double) -> [Stroke] {
        let steps = stepsFor(density: density, min: 200, max: 800)
        var stroke: Stroke = []
        let a = 3.0 + distortion * 0.5
        let b = 4.0 + distortion * 0.3
        let delta = Double.pi / 2
        for i in 0...steps {
            let t = Double(i) / Double(steps) * 2 * .pi * 2
            let x = 0.5 + 0.46 * sin(a * t + delta)
            let y = 0.5 + 0.46 * sin(b * t)
            stroke.append(pt(x, y))
        }
        return [stroke]
    }

    func roseCurve(density: Double, distortion: Double) -> [Stroke] {
        let k = 2.0 + Double(Int(density * 6))
        let steps = stepsFor(density: density, min: 300, max: 800)
        var stroke: Stroke = []
        for i in 0...steps {
            let theta = Double(i) / Double(steps) * 2 * .pi * 2
            let r = wobble(0.46 * abs(cos(k * theta)), distortion: distortion, freq: 8, phase: theta)
            stroke.append(polarPt(r: r, theta: theta))
        }
        return [stroke]
    }

    func hexGrid(density: Double, distortion: Double) -> [Stroke] {
        let size = 0.12 - density * 0.07
        let cols = 3 + Int(density * 6)
        let rows = 3 + Int(density * 5)
        var strokes: [Stroke] = []
        for row in 0..<rows {
            for col in 0..<cols {
                let offsetX = row % 2 == 0 ? 0.0 : size * 1.5 * 0.5
                let hcx = 0.08 + Double(col) * size * 1.5 + offsetX
                let hcy = 0.1 + Double(row) * size * sqrt(3)
                var stroke: Stroke = []
                for i in 0...6 {
                    let angle = Double(i) * .pi / 3
                    let wx = distortion * 0.01 * sin(Double(row + col) * 1.3)
                    let wy = distortion * 0.01 * cos(Double(row * col) * 0.7)
                    let x = hcx + size * 0.9 * cos(angle) + wx
                    let y = hcy + size * 0.9 * sin(angle) + wy
                    stroke.append(pt(x, y))
                }
                strokes.append(stroke)
            }
        }
        return strokes
    }

    func fibonacciSpiral(density: Double, distortion: Double) -> [Stroke] {
        let armCount = 2 + Int(density * 4)
        let turns = 2.0 + density * 5.0
        let steps = stepsFor(density: density)
        var strokes: [Stroke] = []
        for arm in 0..<armCount {
            var stroke: Stroke = []
            let phaseOffset = Double(arm) / Double(armCount) * 2 * .pi
            for i in 0...steps {
                let t = Double(i) / Double(steps)
                let theta = t * turns * 2 * .pi + phaseOffset
                let r = wobble(t * 0.44, distortion: distortion, freq: 8, phase: theta)
                stroke.append(polarPt(r: r, theta: theta))
            }
            strokes.append(stroke)
        }
        return strokes
    }

    func celticWeave(density: Double, distortion: Double) -> [Stroke] {
        let bandCount = 3 + Int(density * 10)
        var strokes: [Stroke] = []
        for b in 0..<bandCount {
            let phase = Double(b) / Double(bandCount) * .pi
            let freq = 2.0 + density * 3.0
            var stroke: Stroke = []
            for i in 0...300 {
                let t = Double(i) / 300.0
                let x = t
                let y = 0.5 + (0.3 + distortion * 0.1) * sin(freq * .pi * t + phase)
                stroke.append(pt(x, y))
            }
            strokes.append(stroke)
        }
        return strokes
    }

    func triquetra(density: Double, distortion: Double) -> [Stroke] {
        // Triquetra = 3 interlocked vesica piscis
        var strokes: [Stroke] = []
        let steps = stepsFor(density: density, min: 200, max: 400)
        let r = 0.28 + density * 0.05
        let offset = r * 0.5

        let centers: [(x: Double, y: Double)] = [
            (cx, cy - offset),
            (cx - offset * cos(.pi / 6), cy + offset * sin(.pi / 6)),
            (cx + offset * cos(.pi / 6), cy + offset * sin(.pi / 6))
        ]

        for (idx, center) in centers.enumerated() {
            var stroke: Stroke = []
            let rotOffset = Double(idx) * 2 * .pi / 3
            for i in 0...steps {
                let theta = Double(i) / Double(steps) * 2 * .pi
                let wobbleR = wobble(r, distortion: distortion, freq: 6, phase: theta)
                let x = center.x + wobbleR * cos(theta + rotOffset)
                let y = center.y + wobbleR * sin(theta + rotOffset)
                stroke.append(pt(x, y))
            }
            strokes.append(stroke)
        }

        // Add the outer circle
        var outer: Stroke = []
        for i in 0...steps {
            let theta = Double(i) / Double(steps) * 2 * .pi
            let wobbleR = wobble(0.44, distortion: distortion, freq: 8, phase: theta)
            outer.append(polarPt(r: wobbleR, theta: theta))
        }
        strokes.append(outer)

        return strokes
    }

    func shieldKnot(density: Double, distortion: Double) -> [Stroke] {
        var strokes: [Stroke] = []
        let steps = 300
        let r = 0.35 + density * 0.05

        // 4 interlocked circles at cardinal positions
        let offsets: [(x: Double, y: Double)] = [
            (0, -0.15), (0.15, 0), (0, 0.15), (-0.15, 0)
        ]

        for (idx, off) in offsets.enumerated() {
            var stroke: Stroke = []
            let rotOffset = Double(idx) * .pi / 2
            for i in 0...steps {
                let theta = Double(i) / Double(steps) * 2 * .pi
                let wobbleR = wobble(r * 0.7, distortion: distortion, freq: 8, phase: theta)
                let x = cx + off.x + wobbleR * cos(theta + rotOffset)
                let y = cy + off.y + wobbleR * sin(theta + rotOffset)
                stroke.append(pt(x, y))
            }
            strokes.append(stroke)
        }

        // Outer boundary circle
        var outer: Stroke = []
        for i in 0...steps {
            let theta = Double(i) / Double(steps) * 2 * .pi
            outer.append(polarPt(r: wobble(0.44, distortion: distortion, freq: 6, phase: theta), theta: theta))
        }
        strokes.append(outer)

        // Inner square
        let sq: [(Double, Double)] = [
            (cx - 0.15, cy - 0.15),
            (cx + 0.15, cy - 0.15),
            (cx + 0.15, cy + 0.15),
            (cx - 0.15, cy + 0.15),
            (cx - 0.15, cy - 0.15)
        ]
        strokes.append(sq.map { pt($0.0, $0.1) })

        return strokes
    }

    func sunburst(density: Double, distortion: Double) -> [Stroke] {
        let arcCount = 8 + Int(density * 40)
        var strokes: [Stroke] = []
        for i in 0..<arcCount {
            let baseAngle = Double(i) / Double(arcCount) * 2 * .pi
            var stroke: Stroke = []
            for j in 0...60 {
                let t = Double(j) / 60.0
                let r = 0.05 + t * 0.41
                let theta = baseAngle + (0.2 + distortion * 0.3) * sin(t * .pi)
                stroke.append(polarPt(r: r, theta: theta))
            }
            strokes.append(stroke)
        }
        return strokes
    }

    func ripple(density: Double, distortion: Double) -> [Stroke] {
        let ringCount = 4 + Int(density * 20)
        var strokes: [Stroke] = []
        for i in 1...ringCount {
            let r = Double(i) / Double(ringCount) * 0.46
            let wobbleAmp = 0.01 + distortion * 0.04
            var stroke: Stroke = []
            for j in 0...300 {
                let theta = Double(j) / 300.0 * 2 * .pi
                let rWobbled = r + wobbleAmp * sin(8 * theta + Double(i) * 0.5)
                stroke.append(polarPt(r: rWobbled, theta: theta))
            }
            strokes.append(stroke)
        }
        return strokes
    }
}
