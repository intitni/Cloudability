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

class MobileArmor: Object, Cloudable {
    @objc dynamic var type = ""
    @objc dynamic var numberOfPilotsNeeded = 1
    let pilots = List<Pilot>()
    
    @objc dynamic var isDeleted = false
}
