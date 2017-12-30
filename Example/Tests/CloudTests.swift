//
//  CloudTests.swift
//  Cloudability_Tests
//
//  Created by Shangxin Guo on 28/12/2017.
//  Copyright © 2017 CocoaPods. All rights reserved.
//

import XCTest
import RealmSwift
import CloudKit
@testable import Cloudability
@testable import Cloudability_Example

class CloudTests: XCTestCase {
    
    override class func setUp() {
        super.setUp()
        Realm.Configuration.defaultConfiguration.inMemoryIdentifier = "memory"
    }
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
        let realm = try! Realm()
        try! realm.write {
            realm.deleteAll()
        }
    }
    
    func testPushThenPull() {
       
    }
}
