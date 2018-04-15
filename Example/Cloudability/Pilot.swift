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

class Pilot: Object, Cloudable, TestableObject {

    @objc dynamic var id: String = UUID().uuidString
    override class func primaryKey() -> String? {
        return "id"
    }
    
    var title: String { return name + " " + id }
    
    override var description: String {
        return """
        Pilot
        ID: \(id)
        Name: \(name)
        Age: \(age)
        """
    }
    
    @objc dynamic var name = ""
    @objc dynamic var age = 18
    var piloting: MobileSuit? = nil
    
    convenience init(name: String, age: Int) {
        self.init()
        self.name = name
        self.age = age
    }
    
    static func createRandom() -> Pilot {
        let firstnames = [
            "Sarah", "Tom", "John", "Johnson", "Tim", "Steve", "Laura", "Sam", "Satoshi"
        ]
        let lastnames = [
            "Battlefiled", "Greenfield", "Strange", "Stark", "Lockon", "Jobs", "Cook", "Yip", "Yamada",
        ]
        let firstname = firstnames[firstnames.indices.random]
        let lastname = lastnames[lastnames.indices.random]
        return Pilot(name: "\(firstname) \(lastname)", age: (15...50).random)
    }
}

extension Range where Bound == Int {
    var random: Int {
        return Int(arc4random_uniform(UInt32(upperBound - lowerBound))) + lowerBound
    }
}

extension ClosedRange where Bound == Int {
    var random: Int {
        return Int(arc4random_uniform(UInt32(upperBound - lowerBound + 1))) + lowerBound
    }
}

extension CountableRange where Bound == Int {
    var random: Int {
        return Int(arc4random_uniform(UInt32(upperBound - lowerBound + 1))) + lowerBound
    }
}
