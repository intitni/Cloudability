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

class MockContainer: Container {
    override init(container: CKContainer) {
        super.init(container: container)
        privateCloudDatabase = MockDatabase(database: container.privateCloudDatabase)
        publicCloudDatabase = MockDatabase(database: container.publicCloudDatabase)
        sharedCloudDatabase = MockDatabase(database: container.sharedCloudDatabase)
    }
}

class MockDatabase: Database {
    override func add(_ operation: CKDatabaseOperation) {
        if let operation = operation as? CKFetchDatabaseChangesOperation {
            operation.changeTokenUpdatedBlock?("changeTokenUpdatedBlock")
            operation.recordZoneWithIDChangedBlock?(CKRecordZoneID(zoneName: "zone", ownerName: CKCurrentUserDefaultName))
            operation.fetchDatabaseChangesCompletionBlock?("fetchDatabaseChangesCompletionBlock", false, nil)
        } else if let operation = operation as? CKFetchRecordZoneChangesOperation {
            let recordZoneIDs = operation.recordZoneIDs
        }
    }
}

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
