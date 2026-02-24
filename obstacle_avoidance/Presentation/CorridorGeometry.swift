//
//  CorridorGeometry.swift
//  obstacle_avoidance
//
//  Created by Elbron Jackob on 02/21/26.
//

import SwiftUI

// Try to see if we can make this an enum to prevent instantiation
struct CorridorGeometry {
    let left: CGRect
    let center: CGRect
    let right: CGRect
}

func calculateCorridor(size:CGSize, stress: CGFloat) -> CorridorGeometry {
    let W = size.width
    let H = size.height
    
    // Base is 2*x so start with 0.5
    let baseCenter: CGFloat = 0.50
    
    // The max the center slice can grow when stress is up to 1
    let maxCenterGrowth: CGFloat = 0.25
    
    // Clamp the stress to the range [0,1]
    let s = max(0, min(1, stress))
    let centerSlice = max(0.45, min(0.80, baseCenter + (s * maxCenterGrowth)))
    
    // Ensure even splits
    let sidePortions = (1.0 - centerSlice) / 2.0
    
    let leftW = W * sidePortions
    let centerW = W * centerSlice
    let rightW = W * sidePortions
    
    let left = CGRect(x: 0, y: 0, width: leftW, height: H)
    let center = CGRect(x: left.maxX, y: 0, width: centerW, height: H)
    let right = CGRect(x: center.maxX, y: 0, width: rightW, height: H)
    
    return CorridorGeometry(left: left, center: center, right: right)
}
