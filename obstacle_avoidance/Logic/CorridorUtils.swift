//
//  CorridorUtils.swift
//  obstacle_avoidance
//
//  Created by Carlos Breach on 4/13/25.
//

import Foundation

struct CorridorUtils {
    enum CorridorPosition {
        case inside
        case left
        case right
        case ahead
    }
    
    static func corridorPosition(_ point: CGPoint, corridor: CorridorGeometry) -> CorridorPosition {

        // 1. Check left slice
        if corridor.left.contains(point) {
            return .left
        }

        // 2. Check center slice
        if corridor.center.contains(point) {
            return .inside   // or .center if you prefer
        }

        // 3. Check right slice
        if corridor.right.contains(point) {
            return .right
        }

        // 4. If not in any slice, it's ahead (outside corridor)
        return .ahead
    }
    
    static func determinePosition(_ bbox: CGRect, corridor: CorridorGeometry) -> String {
        let point = CGPoint(x: bbox.midX, y: bbox.midY)

        switch corridorPosition(point, corridor: corridor) {
        case .left:
            return "Left"
        case .inside:
            return "Center"
        case .right:
            return "Right"
        case .ahead:
            return "Outside"
        }
    }
}
