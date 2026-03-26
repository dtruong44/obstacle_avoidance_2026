//
//  CorridorOverlayView.swift
//  obstacle_avoidance
//
//  Created by Carlos Breach on 4/11/25.
//
import SwiftUI
import Foundation
import AVFoundation

struct CorridorOverlay: View {
    @Binding var corridor: CorridorGeometry?
    var stress: CGFloat

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let geometry = calculateCorridor(size: size, stress: stress)

            ZStack(alignment: .topLeading) {

                // LEFT SLICE
                Rectangle()
                    .fill(Color.red.opacity(0.3))
                    .frame(width: geometry.left.width,
                           height: geometry.left.height)
                    .position(x: geometry.left.midX,
                              y: geometry.left.midY)

                // CENTER SLICE
                Rectangle()
                    .fill(Color.green.opacity(0.3))
                    .frame(width: geometry.center.width,
                           height: geometry.center.height)
                    .position(x: geometry.center.midX,
                              y: geometry.center.midY)

                // RIGHT SLICE
                Rectangle()
                    .fill(Color.blue.opacity(0.3))
                    .frame(width: geometry.right.width,
                           height: geometry.right.height)
                    .position(x: geometry.right.midX,
                              y: geometry.right.midY)
            }
            .onAppear {
                DispatchQueue.main.async {
                    self.corridor = geometry
                }
            }
        }
        .allowsHitTesting(false)
    }
}
