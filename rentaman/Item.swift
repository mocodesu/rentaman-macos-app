//
//  Item.swift
//  rentaman
//
//  Created by Mohamed Abdikafi Abdi on 29/09/2026.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
