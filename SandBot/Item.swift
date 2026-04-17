//
//  Item.swift
//  SandBot
//
//  Created by Anderson Colburn on 4/16/26.
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
