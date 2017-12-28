//
//  Pilot.swift
//  Cloudability_Example
//
//  Created by Shangxin Guo on 03/12/2017.
//  Copyright © 2017 CocoaPods. All rights reserved.
//

import Foundation
import RealmSwift
import Cloudability

class Pilot: Object, Cloudable {
    @objc dynamic var id: String = UUID().uuidString
    override class func primaryKey() -> String? {
        return "id"
    }
    
    @objc dynamic var name = ""
    @objc dynamic var age = 18
    
    @objc dynamic var isDeleted = false
    
    convenience init(name: String, age: Int) {
        self.init()
        self.name = name
        self.age = age
    }
}
