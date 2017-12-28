//
//  ChangeManagerTests.swift
//  Cloudability_Tests
//
//  Created by Shangxin Guo on 27/12/2017.
//  Copyright © 2017 CocoaPods. All rights reserved.
//

import XCTest
import RealmSwift
import CloudKit
@testable import Cloudability
@testable import Cloudability_Example

class ChangeManagerTests: XCTestCase {
    
    override class func setUp() {
        super.setUp()
        Realm.Configuration.defaultConfiguration.inMemoryIdentifier = "memory"
    }
    
    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
        try! r.write { realm in
            realm.deleteAll()
        }
    }
    
    func testSyncedEntityGeneration() {
        let tim: Pilot = {
            let p = Pilot()
            p.age = 21
            p.name = "Tim"
            return p
        }()
        
        try? r.write { realm in
            realm.add(tim)
        }
        
        let changeManager = ChangeManager()
        changeManager.setupSyncedEntitiesIfNeeded()
        
        let syncedEntities = r.syncedEntities
        
        XCTAssert(syncedEntities.count == 1, "SyncedEntities count should be 1, but is \(r.syncedEntities.count)")
        let entity = syncedEntities.first!
        XCTAssert(entity.changeState == .new, "SyncedEntity changeState should be .new, but is \(entity.changeState)")
        
        try? r.write { realm in
            tim.age = 22
        }
        wait(for: 5)
        XCTAssert(entity.changeState == .changed, "SyncedEntity changeState should be .changed, but is \(entity.changeState)")
    }
    
    func testChangeManagerTakeInRecords_SingleModel() {
        let pilotToBeDeleted: Pilot = {
            let p = Pilot()
            p.age = 21
            p.name = "Tim"
            return p
        }()
        
        try? r.write { realm in
            realm.add(pilotToBeDeleted)
        }
        
        let pilotToBeAdded: Pilot = {
            let p = Pilot()
            p.age = 24
            p.name = "John"
            return p
        }()
        
        let recordToBeAdded = ObjectConverter().convert(pilotToBeAdded)
        let recordIDToBeDeleted = CKRecordID(recordName: pilotToBeDeleted.id)
        
        let changeManager = ChangeManager()
        changeManager.setupSyncedEntitiesIfNeeded()
        changeManager.handleSyncronizationGet(modification: [recordToBeAdded], deletion: [recordIDToBeDeleted])
        
        let pilots = r.realm.objects(Pilot.self)
        XCTAssert(pilots.count == 2, " count should be 1, but is \(r.syncedEntities.count)")
        XCTAssert(pilotToBeDeleted.isDeleted == true)
        let addedPilot = pilots.filter({ !$0.isDeleted }).last
        XCTAssertNotNil(addedPilot)
        XCTAssert(addedPilot!.age == pilotToBeAdded.age)
        XCTAssert(addedPilot!.name == pilotToBeAdded.name)
        XCTAssert(addedPilot!.id == pilotToBeAdded.id)
        
        let syncedEntities = r.syncedEntities
        XCTAssert(syncedEntities.count == 2, "SyncedEntities count should be 2, but is \(r.syncedEntities.count)")
        for s in syncedEntities {
            XCTAssert(s.changeState == .synced)
        }
    }
}

extension ChangeManagerTests {
    private func generateFullSetTestData() {
        let tim: Pilot = {
            let p = Pilot()
            p.age = 21
            p.name = "Tim"
            return p
        }()
        
        let john: Pilot = {
            let p = Pilot()
            p.age = 24
            p.name = "John"
            return p
        }()
        
        let sarah: Pilot = {
            let p = Pilot()
            p.age = 30
            p.name = "Sarah"
            return p
        }()
        
        let gundam: MobileSuit = {
            let m = MobileSuit()
            m.pilot = tim
            m.type = "ZZZ"
            return m
        }()
        
        let armor: MobileArmor = {
            let m = MobileArmor()
            m.pilots.append(objectsIn: [john, tim])
            m.numberOfPilotsNeeded = 2
            m.type = "AAA"
            return m
        }()
        
        let battleShip: BattleShip = {
            let s = BattleShip()
            s.mobileArmors.append(armor)
            s.mobileSuits.append(gundam)
            s.msCatapults = 4
            s.name = "Ship"
            return s
        }()
        
        try? r.write { realm in
            realm.add(tim)
            realm.add(john)
            realm.add(sarah)
            realm.add(gundam)
            realm.add(armor)
            realm.add(battleShip)
        }
    }
    
    func wait(for duration: TimeInterval) {
        let waitExpectation = expectation(description: "Waiting")
        
        let when = DispatchTime.now() + duration
        DispatchQueue.main.asyncAfter(deadline: when) {
            waitExpectation.fulfill()
        }
        
        waitForExpectations(timeout: duration + 0.5)
    }
}
