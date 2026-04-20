//
//  SandCanvas.swift
//  SandBot
//
//  Created by Anderson Colburn on 4/19/26.
//

import SwiftUI

struct SandCanvas: View {
    let strokes: [Stroke]
    var animated: Bool = false

    var body: some View {
        Canvas { context, size in
            for stroke in strokes {
                guard stroke.count > 1 else { continue }
                var path = Path()
                let first = stroke[0]
                path.move(to: CGPoint(
                    x: first.x * size.width,
                    y: first.y * size.height
                ))
                for point in stroke.dropFirst() {
                    path.addLine(to: CGPoint(
                        x: point.x * size.width,
                        y: point.y * size.height
                    ))
                }
                context.stroke(path,
                    with: .color(Color.sandGold),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                )
            }
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
    }
}
