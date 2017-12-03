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

class BattleShip: Object, Cloudable {
    var mobileSuits = List<MobileSuit>()
    var mobileArmors = List<MobileArmor>()
    @objc dynamic var name = ""
    @objc dynamic var msCatapults = 1
    
    @objc dynamic var isDeleted = false
}
