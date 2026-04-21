//
//  EdgeDetectionService.swift
//  SandBot
//
//  Created by Anderson Colburn on 4/20/26.
//


import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

final class EdgeDetectionService {
    static let shared = EdgeDetectionService()
    private let context = CIContext()

    func detectEdges(from image: UIImage, threshold: Float = 0.5) -> [Stroke] {
        guard let cgImage = image.cgImage else { return [] }
        let ciImage = CIImage(cgImage: cgImage)

        // Convert to grayscale
        let grayscale = ciImage.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0.0
        ])

        // Edge detection using Sobel
        let edges = grayscale.applyingFilter("CIEdges", parameters: [
            kCIInputIntensityKey: 5.0
        ])

        // Threshold to clean up noise
        let thresholded = edges.applyingFilter("CIColorThreshold", parameters: [
            "inputThreshold": threshold
        ])

        guard let outputCGImage = context.createCGImage(thresholded, from: thresholded.extent) else {
            return []
        }

        return extractStrokes(from: outputCGImage)
    }

    private func extractStrokes(from cgImage: CGImage) -> [Stroke] {
        let width = cgImage.width
        let height = cgImage.height
        guard let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return [] }

        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow

        var visited = Array(repeating: Array(repeating: false, count: width), count: height)
        var strokes: [Stroke] = []

        // Walk edge pixels and group them into strokes using simple connectivity
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let brightness = bytes[offset]

                if brightness > 128 && !visited[y][x] {
                    // Trace a stroke from this edge pixel
                    let stroke = traceStroke(
                        from: (x, y),
                        bytes: bytes,
                        bytesPerRow: bytesPerRow,
                        bytesPerPixel: bytesPerPixel,
                        width: width,
                        height: height,
                        visited: &visited
                    )
                    if stroke.count > 5 {
                        let normalized = stroke.map {
                            StrokePoint(
                                x: Double($0.0) / Double(width),
                                y: Double($0.1) / Double(height)
                            )
                        }
                        strokes.append(normalized)
                    }
                }
            }
        }

        return strokes
    }

    private func traceStroke(
        from start: (Int, Int),
        bytes: UnsafePointer<UInt8>,
        bytesPerRow: Int,
        bytesPerPixel: Int,
        width: Int,
        height: Int,
        visited: inout [[Bool]]
    ) -> [(Int, Int)] {
        var result: [(Int, Int)] = []
        var queue: [(Int, Int)] = [start]
        var count = 0
        let maxPoints = 500

        while !queue.isEmpty && count < maxPoints {
            let (x, y) = queue.removeFirst()
            guard x >= 0, x < width, y >= 0, y < height,
                  !visited[y][x] else { continue }

            let offset = y * bytesPerRow + x * bytesPerPixel
            let brightness = bytes[offset]
            guard brightness > 128 else { continue }

            visited[y][x] = true
            result.append((x, y))
            count += 1

            // 8-connected neighbors
            for dy in -1...1 {
                for dx in -1...1 {
                    if dx == 0 && dy == 0 { continue }
                    queue.append((x + dx, y + dy))
                }
            }
        }

        return result
    }
}