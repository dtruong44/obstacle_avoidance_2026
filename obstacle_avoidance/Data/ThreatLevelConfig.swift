//
//  ThreatLevelConfig.swift
//  obstacle_avoidance
//
//  Created by Darien Aranda on 2/20/25.
//

import Foundation

struct ThreatLevelConfig {

    static let angleWeights: [Int: Int] = [
        12: 10,
        11: 4,
        1: 4,
        10: 2,
        2: 2
    ]

    static let objectWeights: [Int: Int] = [
        0: 6,    // Bench
        1: 15,   // Bicycle (moving)
        2: 7,    // Branch
        3: 12,   // Bus
        4: 5,    // Bushes
        5: 12,   // Car
        6: 7,    // Crosswalk
        7: 7,    // Door
        8: 6,    // Elevator
        9: 6,    // Fire Hydrant
        10: 15,  // Person (moving)
        11: 14,  // Scooter (moving)
        12: 14,  // Motorcycle (moving)
        13: 15,  // Stairs
        14: 10,  // Stop Sign
        15: 7,   // Traffic Cone
        16: 10,  // Tree
        17: 12,  // Truck
        18: 6,   // Trash Can
        19: 6,   // Chair
        20: 6,   // Table
        21: 5,   // Small Animal
        22: 10   // Large Animal
    ]

    static let objectName: [Int: String] = [
        0: "Bench",
        1: "Bicycle",
        2: "Branch",
        3: "Bus",
        4: "Bushes",
        5: "Car",
        6: "Crosswalk",
        7: "Door",
        8: "Elevator",
        9: "Fire Hydrant",
        10: "Person",
        11: "Scooter",
        12: "Motorcycle",
        13: "Stairs",
        14: "Stop Sign",
        15: "Traffic Cone",
        16: "Tree",
        17: "Truck",
        18: "Trash Can",
        19: "Chair",
        20: "Table",
        21: "Small Animal",
        22: "Large Animal"
    ]
}
