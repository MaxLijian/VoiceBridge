//
//  Item.swift
//  VoiceBridge
//
//  Created by YanDong Li on 3/21/26.
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
