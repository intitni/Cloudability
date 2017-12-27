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

class MobileSuit: Object, Cloudable {
    @objc dynamic var id: String = UUID().uuidString
    override class func primaryKey() -> String? {
        return "id"
    }
    
    @objc dynamic var type = ""
    @objc dynamic var pilot: Pilot?
    
    @objc dynamic var isDeleted = false
}
