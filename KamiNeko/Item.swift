//
//  Item.swift
//  KamiNeko
//
//  Created by tetsuya on 2025/09/06.
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
