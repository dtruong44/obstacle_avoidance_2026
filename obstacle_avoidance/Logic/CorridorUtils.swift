// CorridorUtils.swift

import Foundation
import CoreGraphics

struct CorridorUtils {
    
    static func determinePosition(_ bbox: CGRect, corridor: CorridorGeometry) -> String {
        var leftHits = 0
        var centerHits = 0
        var rightHits = 0

        // 1. Count intersections in the 3 Left strips
        for strip in corridor.leftStrips {
            if bbox.intersects(strip.rect) {
                leftHits += 1
            }
        }

        // 2. Count intersections in the 3 Center strips
        for strip in corridor.centerStrips {
            if bbox.intersects(strip.rect) {
                centerHits += 1
            }
        }

        // 3. Count intersections in the 3 Right strips
        for strip in corridor.rightStrips {
            if bbox.intersects(strip.rect) {
                rightHits += 1
            }
        }

        // 4. Majority Rules Determination
        // If an object hits more strips in one zone than others, it's assigned there.
        let counts = ["Left": leftHits, "Center": centerHits, "Right": rightHits]
        
        // Find the zone with the highest number of hits
        if let maxHit = counts.max(by: { $0.value < $1.value }), maxHit.value > 0 {
            return maxHit.key
        }

        return "Outside"
    }
}