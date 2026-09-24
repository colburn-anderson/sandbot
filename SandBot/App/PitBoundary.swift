//
//  PitBoundary.swift
//  SandBot
//
//  The kidney-shaped sand pit outline, in arm coordinates (mm). The bridge
//  owns the real outline (GET /boundary); the app caches it so the canvas
//  and previews always look like the actual pit.
//

import SwiftUI
import Combine

struct PitBoundary: Codable, Equatable {
    var polygon: [[Double]]
    var safeZ: Double
    var marginMm: Double
    var calibrated: Bool

    enum CodingKeys: String, CodingKey {
        case polygon
        case safeZ = "safe_z"
        case marginMm = "margin_mm"
        case calibrated
    }

    var minX: Double { polygon.map { $0[0] }.min() ?? 0 }
    var maxX: Double { polygon.map { $0[0] }.max() ?? 1 }
    var minY: Double { polygon.map { $0[1] }.min() ?? 0 }
    var maxY: Double { polygon.map { $0[1] }.max() ?? 1 }
    var aspectRatio: CGFloat { viewport.aspectRatio }

    /// The pit's bounding box — the drawing canvas covers exactly this.
    var viewport: PitViewport { PitViewport(minX: minX, maxX: maxX, minY: minY, maxY: maxY) }

    func point(x: Double, y: Double, in rect: CGRect) -> CGPoint {
        viewport.point(x: x, y: y, in: rect)
    }

    // Mirrors DEFAULT_POLYGON in the bridge's boundary.py (estimated from photos).
    static let `default`: PitBoundary = {
        let half: [(Double, Double)] = [
            (0, 255), (59, 247), (104, 225), (134, 195), (147, 156), (149, 113),
            (142, 73), (127, 40), (104, 24), (79, 27), (59, 44), (39, 63), (19, 73),
        ]
        let left = half.map { [-$0.0, $0.1] }
        let right = half.dropFirst().reversed().map { [$0.0, $0.1] }
        return PitBoundary(polygon: left + [[0, 75]] + right, safeZ: 200, marginMm: 8, calibrated: false)
    }()
}

/// A rectangle of arm space (mm) mapped onto a view. Top = far side of the
/// pit (max Y), matching the bridge's canvas.
struct PitViewport: Equatable {
    var minX, maxX, minY, maxY: Double

    var aspectRatio: CGFloat { CGFloat((maxX - minX) / max(maxY - minY, 1)) }

    func point(x: Double, y: Double, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + (x - minX) / (maxX - minX) * rect.width,
            y: rect.minY + (maxY - y) / (maxY - minY) * rect.height
        )
    }

    /// Grow to include the given points, plus padding.
    func including(_ points: [[Double]], padding: Double = 0) -> PitViewport {
        let xs = points.map { $0[0] } + [minX, maxX]
        let ys = points.map { $0[1] } + [minY, maxY]
        return PitViewport(minX: xs.min()! - padding, maxX: xs.max()! + padding,
                           minY: ys.min()! - padding, maxY: ys.max()! + padding)
    }
}

/// The pit outline as a SwiftUI shape, scaled to fill its frame.
struct PitShape: Shape {
    let boundary: PitBoundary
    var viewport: PitViewport? = nil

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let vp = viewport ?? boundary.viewport
        guard let first = boundary.polygon.first else { return path }
        path.move(to: vp.point(x: first[0], y: first[1], in: rect))
        for p in boundary.polygon.dropFirst() {
            path.addLine(to: vp.point(x: p[0], y: p[1], in: rect))
        }
        path.closeSubpath()
        return path
    }
}

@MainActor
final class PitBoundaryStore: ObservableObject {
    static let shared = PitBoundaryStore()

    @Published private(set) var boundary: PitBoundary

    private let cacheKey = "pitBoundary"

    private init() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(PitBoundary.self, from: data) {
            boundary = cached
        } else {
            boundary = .default
        }
    }

    func refresh() async {
        guard let fresh = try? await RobotService.shared.fetchBoundary() else { return }
        update(fresh)
    }

    func update(_ fresh: PitBoundary) {
        boundary = fresh
        if let data = try? JSONEncoder().encode(fresh) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }
}

/// A pit-shaped backdrop: sand-colored kidney with its rim outlined.
struct PitBackdrop: View {
    let boundary: PitBoundary

    var body: some View {
        ZStack {
            PitShape(boundary: boundary)
                .fill(Color.sandSurface)
            PitShape(boundary: boundary)
                .stroke(Color.sandGold.opacity(0.6), lineWidth: 2)
        }
        .aspectRatio(boundary.aspectRatio, contentMode: .fit)
    }
}
