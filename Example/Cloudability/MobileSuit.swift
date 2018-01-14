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
    @objc dynamic var pilot: Pilot?
    
    var title: String { return type + " " + id }
    
    override var description: String {
        return """
        Mobile Suit
        ID: \(id)
        Type: \(type)
        
        ----------
        Pilot: \(pilot?.description ?? "none")
        """
    }
    
    convenience init(type: String, pilot: Pilot) {
        self.init()
        self.type = type
        self.pilot = pilot
    }
}
