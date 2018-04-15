//
//  MobileSuit.swift
//  Cloudability_Example
//
//  Created by Shangxin Guo on 03/12/2017.
//  Copyright © 2017 CocoaPods. All rights reserved.
//

import Foundation
import RealmSwift
import Cloudability

class MobileSuit: Object, Cloudable, TestableObject {

    @objc dynamic var id: String = UUID().uuidString
    override class func primaryKey() -> String? {
        return "id"
    }
    
    @objc dynamic var type = ""
    let pilots = LinkingObjects(fromType: Pilot.self, property: "piloting")
    var onShip: BattleShip? = nil
    
    var title: String { return type + " " + id }
    
    override var description: String {
        return """
        Mobile Suit
        ID: \(id)
        Type: \(type)
        
        ----------
        Pilot: \(pilots.first?.description ?? "none")
        """
    }
    
    convenience init(type: String) {
        self.init()
        self.type = type
    }
    
    static func createRandom() -> MobileSuit {
        let types = ["RX0"]
        return MobileSuit(type: types[types.indices.random])
    }
}
