//  CorridorOverlay.swift
import SwiftUI

struct CorridorOverlay: View {
    @Binding var corridor: CorridorGeometry?
    var stress: CGFloat

    var body: some View {
        GeometryReader { geo in
            let geometry = calculateCorridor(size: geo.size, stress: stress)

            ZStack(alignment: .topLeading) {
//                 Loop through and render all 9 unique strips
                ForEach(0..<3) { i in
                    renderStrip(geometry.leftStrips[i])
                    renderStrip(geometry.centerStrips[i])
                    renderStrip(geometry.rightStrips[i])
                }
            }
            .onAppear {
                DispatchQueue.main.async {
                    self.corridor = geometry
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func renderStrip(_ strip: (rect: CGRect, color: Color)) -> some View {
        Rectangle()
            .fill(strip.color.opacity(0.35)) // Slightly higher opacity to see the colors clearly
            .frame(width: strip.rect.width, height: strip.rect.height)
            .position(x: strip.rect.midX, y: strip.rect.midY)
            .border(strip.color.opacity(0.5), width: 1) // Optional: adds a thin line between strips
    }
}
