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
    
    let mobileSuits = LinkingObjects(fromType: MobileSuit.self, property: "onShip")
    @objc dynamic var name = ""
    @objc dynamic var msCatapults = 1
    
    var title: String { return name + " " + id }
    
    override var description: String {
        return """
        Battle Ship
        ID: \(id)
        Name: \(name)
        MS Catapults: \(msCatapults)
        
        ----------
        Mobile Suits: \(mobileSuits)

        """
    }
    
    convenience init(name: String, msCatapults: Int) {
        self.init()
        self.name = name
        self.msCatapults = msCatapults
    }
    
    static func createRandom() -> BattleShip {
        let names = ["Arc Angel"]
        return BattleShip(name: names[names.indices.random], msCatapults: (5...10).random)
    }
}
