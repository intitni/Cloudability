//
//  BattleShip.swift
//  Cloudability_Example
//
//  Created by Shangxin Guo on 03/12/2017.
//  Copyright © 2017 CocoaPods. All rights reserved.
//

import Foundation
import RealmSwift
import Cloudability

class BattleShip: Object, Cloudable, TestableObject {
    @objc dynamic var id: String = UUID().uuidString
    override class func primaryKey() -> String? {
        return "id"
    }
    
    var mobileSuits = List<MobileSuit>()
    var mobileArmors = List<MobileArmor>()
    @objc dynamic var name = ""
    @objc dynamic var msCatapults = 1
    
    var title: String { return name + " " + id }
    
    override var description: String {
        return """
        Battle Ship
        ID: \(id)
        Name: \(name)
        
        ----------
        Mobile Suits: \(mobileSuits)
        
        ----------
        Mobile Armors: \(mobileArmors)
        """
    }
    
    convenience init(name: String, msCatapults: Int, mobileSuits: [MobileSuit], mobileArmors: [MobileArmor]) {
        self.init()
        self.name = name
        self.msCatapults = msCatapults
        self.mobileSuits.append(objectsIn: mobileSuits)
        self.mobileArmors.append(objectsIn: mobileArmors)
    }
}
