//
//  MobileArmor.swift
//  Cloudability_Example
//
//  Created by Shangxin Guo on 03/12/2017.
//  Copyright © 2017 CocoaPods. All rights reserved.
//

import Foundation
import RealmSwift
import Cloudability

class MobileArmor: Object, Cloudable, TestableObject {
    @objc dynamic var id: String = UUID().uuidString
    override class func primaryKey() -> String? {
        return "id"
    }
    
    @objc dynamic var type = ""
    @objc dynamic var numberOfPilotsNeeded = 1
    let pilots = List<Pilot>()
    
    var title: String { return type + " " + id }
    
    override var description: String {
        return """
        Mobile Armor
        ID: \(id)
        Type: \(type)
        Needs Pilot: \(numberOfPilotsNeeded)
        
        ----------
        Pilots: \(pilots)
        """
    }
    
    convenience init(type: String, numberOfPilotsNeeded: Int, pilots: [Pilot]) {
        self.init()
        self.type = type
        self.numberOfPilotsNeeded = numberOfPilotsNeeded
        self.pilots.append(objectsIn: pilots)
    }
}
