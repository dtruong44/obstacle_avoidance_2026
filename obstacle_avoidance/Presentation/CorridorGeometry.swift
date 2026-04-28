//  CorridorGeometry.swift
import SwiftUI

struct CorridorGeometry {
    let leftStrips: [(rect: CGRect, color: Color)]
    let centerStrips: [(rect: CGRect, color: Color)]
    let rightStrips: [(rect: CGRect, color: Color)]
}

func calculateCorridor(size: CGSize, stress: CGFloat) -> CorridorGeometry {
    let W = size.width
    let H = size.height

    let s = max(0, min(1, stress))
    let centerSlice = max(0.45, min(0.80, 0.50 + (s * 0.25)))
    let sidePortions = (1.0 - centerSlice) / 2.0

    let leftW = W * sidePortions
    let centerW = W * centerSlice
    let rightW = W * sidePortions

    // Helper to generate 3 individual strips with unique hues
    func getColoredStrips(xOffset: CGFloat, totalW: CGFloat, startHue: Double) -> [(CGRect, Color)] {
        let stripW = totalW / 3.0
        return (0..<3).map { i in
            let rect = CGRect(x: xOffset + (CGFloat(i) * stripW), y: 0, width: stripW, height: H)
            
            // Increment hue by 0.1 for every single strip (9 strips total = 0.9 of the hue spectrum)
            let currentHue = startHue + (Double(i) * 0.1)
            let color = Color(hue: currentHue, saturation: 0.8, brightness: 0.9)
            
            return (rect, color)
        }
    }

    return CorridorGeometry(
        // Start hues are spaced out so the 3 groups don't overlap colors
        leftStrips: getColoredStrips(xOffset: 0, totalW: leftW, startHue: 0.0),          // 0.0, 0.1, 0.2
        centerStrips: getColoredStrips(xOffset: leftW, totalW: centerW, startHue: 0.3),  // 0.3, 0.4, 0.5
        rightStrips: getColoredStrips(xOffset: leftW + centerW, totalW: rightW, startHue: 0.6) // 0.6, 0.7, 0.8
    )
}