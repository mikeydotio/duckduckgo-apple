//
//  FloatingHint.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import SwiftUI
import DesignResourcesKit

struct FloatingHint: View {

    let text: String
    @State private var isBouncing = false

    // Arrowhead V occupies the top 14pt; remaining 31pt is the visible shaft below it.
    private let arrowHeight: CGFloat = 45

    init(text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 17, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .padding(.top, arrowHeight)
            .background(
                FloatingHintShape(arrowHeight: arrowHeight)
                    .fill(accentColor)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 20, x: 0, y: 4)
            .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
            .offset(y: isBouncing ? -8 : 0)
            .animation(
                .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                value: isBouncing
            )
            .onAppear {
                isBouncing = true
            }
    }

    private var accentColor: Color {
        Color(singleUseColor: .fireModeAccent)
    }
}

/// Single continuous outline that combines an up-arrow at top with a pill at bottom — the
/// silhouette matches Figma's `Union` SVG export. Rendering as one shape (vs. composing
/// separate views) ensures the arrow tail visually merges into the pill body without seams.
private struct FloatingHintShape: Shape {

    /// Vertical space reserved for the arrow above the pill (in rect coordinates).
    let arrowHeight: CGFloat

    /// Thickness of the vertical arrow shaft.
    var shaftThickness: CGFloat = 6

    /// Corner radius of the pill body. Auto-clamped so it never exceeds half the pill height.
    var pillCornerRadius: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        Path { path in
            let midX = rect.midX
            let halfShaft = shaftThickness / 2

            let apexY = rect.minY
            let pillTopY = rect.minY + arrowHeight
            let pillBottomY = rect.maxY

            let pillLeft = rect.minX
            let pillRight = rect.maxX

            let pillHeight = pillBottomY - pillTopY
            let radius = min(pillCornerRadius, pillHeight / 2)

            // ----- Pill -----
            path.addRoundedRect(
                in: CGRect(x: pillLeft,
                           y: pillTopY,
                           width: pillRight - pillLeft,
                           height: pillHeight),
                cornerSize: CGSize(width: radius, height: radius)
            )

            // ----- Shaft (vertical rectangle from apex down to pill top) -----
            path.addRoundedRect(
                in: CGRect(x: midX - halfShaft,
                           y: apexY,
                           width: shaftThickness,
                           height: pillTopY - apexY),
                cornerSize: CGSize(width: 2, height: 2)
            )

            // ----- Arrowhead arms (two chunky diagonal rectangles forming a V) -----
            // Each arm is a vertical rectangle that we rotate ±45° around the apex.
            // Arm length here is the centerline length along its long axis.
            let armLength: CGFloat = 26
            let armRect = CGRect(
                x: -shaftThickness / 2,
                y: 0,
                width: shaftThickness,
                height: armLength
            )
            let armCorner = CGSize(width: 2, height: 2)

            // LEFT arm: pivot at apex (nudged slightly right to tighten the V tip),
            // rotate so the arm extends down-and-to-the-left.
            let leftTransform = CGAffineTransform(translationX: midX + 1.5, y: apexY)
                .rotated(by: .pi / 4)
            path.addPath(Path(roundedRect: armRect, cornerSize: armCorner), transform: leftTransform)

            // RIGHT arm: pivot at apex (nudged slightly left to tighten the V tip),
            // rotate so the arm extends down-and-to-the-right.
            let rightTransform = CGAffineTransform(translationX: midX - 1.5, y: apexY)
                .rotated(by: -.pi / 4)
            path.addPath(Path(roundedRect: armRect, cornerSize: armCorner), transform: rightTransform)
        }
    }
}

#Preview("Tap allow") {
    FloatingHint(text: "Tap allow")
        .padding()
        .background(Color(designSystemColor: .surface))
}

#Preview("Custom text") {
    FloatingHint(text: "Tap here to continue")
        .padding()
        .background(Color(designSystemColor: .surface))
}

#Preview("On dimmed background") {
    ZStack {
        Color.black.opacity(0.4)
            .ignoresSafeArea()
        FloatingHint(text: "Tap allow")
    }
}
