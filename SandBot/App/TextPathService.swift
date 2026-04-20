//
//  TextPathService.swift
//  SandBot
//
//  Created by Anderson Colburn on 4/19/26.
//

import Foundation
import CoreText
import CoreGraphics
import UIKit

final class TextPathService {
    static let shared = TextPathService()

    func strokes(from text: String, fontName: String, fontSize: CGFloat = 200) -> [Stroke] {
        let font = CTFontCreateWithName(fontName as CFString, fontSize * 0.7, nil)
        let attributedString = NSAttributedString(
            string: text,
            attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
        )

        let line = CTLineCreateWithAttributedString(attributedString)
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]

        var glyphPaths: [CGPath] = []

        for run in runs {
            let glyphCount = CTRunGetGlyphCount(run)
            let attributes = CTRunGetAttributes(run) as! [NSAttributedString.Key: Any]
            guard let runFont = attributes[kCTFontAttributeName as NSAttributedString.Key] as! CTFont? else { continue }

            for i in 0..<glyphCount {
                var glyph = CGGlyph()
                var position = CGPoint.zero
                CTRunGetGlyphs(run, CFRangeMake(i, 1), &glyph)
                CTRunGetPositions(run, CFRangeMake(i, 1), &position)

                guard let path = CTFontCreatePathForGlyph(runFont, glyph, nil) else { continue }

                // Flip Y axis and translate to position
                var transform = CGAffineTransform(scaleX: 1, y: -1)
                    .translatedBy(x: position.x, y: -position.y)
                if let transformed = path.copy(using: &transform) {
                    glyphPaths.append(transformed)
                }
            }
        }

        // Get overall bounding box for normalization
        let allPointsPath = CGMutablePath()
        glyphPaths.forEach { allPointsPath.addPath($0) }
        var bounds = allPointsPath.boundingBox
        let padding = bounds.width * 0.05
        bounds = bounds.insetBy(dx: -padding, dy: -padding)
        guard bounds.width > 0, bounds.height > 0 else { return [] }

        // Convert each glyph path into clean subpath strokes
        var strokes: [Stroke] = []
        for glyphPath in glyphPaths {
            let subpaths = extractSubpaths(from: glyphPath, bounds: bounds)
            strokes.append(contentsOf: subpaths)
        }

        return strokes
    }

    /// Splits a CGPath into individual subpaths, each becoming its own stroke
    private func extractSubpaths(from path: CGPath, bounds: CGRect) -> [Stroke] {
        var result: [Stroke] = []
        var current: Stroke = []
        var currentPoint = CGPoint.zero

        path.applyWithBlock { elementPtr in
            let element = elementPtr.pointee
            switch element.type {
            case .moveToPoint:
                // Pen lift — save current stroke and start fresh
                if current.count > 1 {
                    result.append(current)
                }
                current = []
                currentPoint = element.points[0]
                current.append(self.normalize(currentPoint, bounds: bounds))

            case .addLineToPoint:
                let p = element.points[0]
                current.append(self.normalize(p, bounds: bounds))
                currentPoint = p

            case .addCurveToPoint:
                let cp1 = element.points[0]
                let cp2 = element.points[1]
                let end = element.points[2]
                let sampled = self.sampleCubicBezier(from: currentPoint, cp1: cp1, cp2: cp2, to: end, steps: 24)
                current.append(contentsOf: sampled.map { self.normalize($0, bounds: bounds) })
                currentPoint = end

            case .addQuadCurveToPoint:
                let cp = element.points[0]
                let end = element.points[1]
                let sampled = self.sampleQuadBezier(from: currentPoint, cp: cp, to: end, steps: 24)
                current.append(contentsOf: sampled.map { self.normalize($0, bounds: bounds) })
                currentPoint = end

            case .closeSubpath:
                // Close the loop back to start, then lift pen
                if let first = current.first {
                    current.append(first)
                }
                if current.count > 1 {
                    result.append(current)
                }
                current = []

            @unknown default:
                break
            }
        }

        if current.count > 1 {
            result.append(current)
        }

        return result
    }

    private func normalize(_ point: CGPoint, bounds: CGRect) -> StrokePoint {
        let x = Double((point.x - bounds.minX) / bounds.width)
        let y = Double((point.y - bounds.minY) / bounds.height)
        return StrokePoint(x: max(0, min(1, x)), y: max(0, min(1, y)))
    }

    private func sampleCubicBezier(from p0: CGPoint, cp1: CGPoint, cp2: CGPoint, to p3: CGPoint, steps: Int) -> [CGPoint] {
        var result: [CGPoint] = []
        for i in 0...steps {
            let t: CGFloat = CGFloat(i) / CGFloat(steps)
            let u: CGFloat = 1 - t
            let x: CGFloat = u*u*u*p0.x + 3*u*u*t*cp1.x + 3*u*t*t*cp2.x + t*t*t*p3.x
            let y: CGFloat = u*u*u*p0.y + 3*u*u*t*cp1.y + 3*u*t*t*cp2.y + t*t*t*p3.y
            result.append(CGPoint(x: x, y: y))
        }
        return result
    }

    private func sampleQuadBezier(from p0: CGPoint, cp: CGPoint, to p2: CGPoint, steps: Int) -> [CGPoint] {
        var result: [CGPoint] = []
        for i in 0...steps {
            let t: CGFloat = CGFloat(i) / CGFloat(steps)
            let u: CGFloat = 1 - t
            let x: CGFloat = u*u*p0.x + 2*u*t*cp.x + t*t*p2.x
            let y: CGFloat = u*u*p0.y + 2*u*t*cp.y + t*t*p2.y
            result.append(CGPoint(x: x, y: y))
        }
        return result
    }
}
