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
    @objc dynamic var name = ""
    @objc dynamic var age = 18
    
    @objc dynamic var isDeleted = false
}