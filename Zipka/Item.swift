//
//  Item.swift
//  Zipka
//
//  Created by Jakub Majka on 4/12/25.
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
