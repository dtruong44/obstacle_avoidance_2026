//
//  CorridorGeometry.swift
//  obstacle_avoidance
//
//  Created by Elbron Jackob on 02/21/26.
//

import SwiftUI

struct CorridorGeometry {
    let left: [(rect: CGRect, color: Color)]
    let center: [(rect: CGRect, color: Color)]
    let right: [(rect: CGRect, color: Color)]
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

    func getColoredStrips(xOffset: CGFloat, totalW: CGFloat, baseHue: Double) -> [(CGRect, Color)] {
        let stripW = totalW / 3.0
        return (0..<3).map { i in
            let rect = CGRect(x: xOffset + (CGFloat(i) * stripW), y: 0, width: stripW, height: H)
            // Generate a color based on the index to ensure they are distinct
            let color = Color(hue: baseHue + (Double(i) * 0.05), saturation: 0.7, brightness: 0.8)
            return (rect, color)
        }
    }

    return CorridorGeometry(
        left: getColoredStrips(xOffset: 0, totalW: leftW, baseHue: 0.0),
        center: getColoredStrips(xOffset: leftW, totalW: centerW, baseHue: 0.3),
        right: getColoredStrips(xOffset: leftW + centerW, totalW: rightW, baseHue: 0.6)
    )
}
