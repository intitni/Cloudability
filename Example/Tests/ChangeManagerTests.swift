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
        let realm = try! Realm()
        try! realm.write {
            realm.deleteAll()
        }
    }
    
    func testSyncedEntityGeneration() {
        let realm = try! Realm()
        let tim = Pilot(name: "Tim", age: 21)
        
        try? realm.write {
            realm.add(tim)
        }
        
        let changeManager = ChangeManager()
        changeManager.setupSyncedEntitiesIfNeeded()
        
        let syncedEntities = r.syncedEntities
        
        XCTAssert(syncedEntities.count == 1, "SyncedEntities count should be 1, but is \(syncedEntities.count)")
        let entity = syncedEntities.first!
        XCTAssert(entity.changeState == .new, "SyncedEntity changeState should be .new, but is \(entity.changeState)")
        
        try? realm.write {
            tim.age = 22
        }
        wait(for: 5)
        XCTAssert(entity.changeState == .changed, "SyncedEntity changeState should be .changed, but is \(entity.changeState)")
    }
    
    func testChangeManagerTakeInRecords_SingleModel() {
        let realm = try! Realm()
        let pilotToBeDeleted = Pilot(name: "Tim", age: 21)
        
        try? realm.write {
            realm.add(pilotToBeDeleted)
        }
        
        let pilotToBeAdded = Pilot(name: "John", age: 24)
        
        let recordToBeAdded = ObjectConverter().convert(pilotToBeAdded)
        let recordIDToBeDeleted = CKRecordID(recordName: pilotToBeDeleted.id)
        
        let changeManager = ChangeManager()
        changeManager.setupSyncedEntitiesIfNeeded()
        changeManager.handleSyncronizationGet(modification: [recordToBeAdded], deletion: [recordIDToBeDeleted])
        
        // Assertion
        
        let pilots = realm.objects(Pilot.self)
        XCTAssert(pilots.count == 1, " count should be 1, but is \(pilots.count)")
        XCTAssert(pilotToBeDeleted.isInvalidated)
        let addedPilot = pilots.last
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
    
    func testChangeManagerTakeInRecord_SpaghettiModel() {
        let realm = try! Realm()
        let tim = Pilot(name: "Tim", age: 21)
        let john = Pilot(name: "John", age: 24)
        let sarah = Pilot(name: "Sarah", age: 30)
        
        let gundam = MobileSuit(type: "ZZZ", pilot: tim)
        let armor = MobileArmor(type: "AAA", numberOfPilotsNeeded: 2, pilots: [john, tim])
        
        let battleShip = BattleShip(name: "Ship", msCatapults: 4, mobileSuits: [gundam], mobileArmors: [armor])
        
        try? realm.write {
            realm.add(tim)
            realm.add(john)
            realm.add(sarah)
            realm.add(gundam)
            realm.add(armor)
            realm.add(battleShip)
        }
        
        let changeManager = ChangeManager()
        changeManager.setupSyncedEntitiesIfNeeded()
        
        let pilots = realm.objects(Pilot.self)
        let recordIDToBeDeleted = [CKRecordID(recordName: tim.id), CKRecordID(recordName: gundam.id)]
        
        let newSarah = Pilot(value: sarah)
        newSarah.age = 17 // girl's age should not exceed 18
        let steve = Pilot(name: "Steve", age: 23)
        let newGundam = MobileSuit(type: "MMM", pilot: sarah)
        let lucus = Pilot(name: "Lucus", age: 18)
        let newArmor = MobileArmor(type: "BBB", numberOfPilotsNeeded: 2, pilots: [steve, tim])
        let newBattleShip = BattleShip(name: "NewShip", msCatapults: 3, mobileSuits: [newGundam], mobileArmors: [newArmor])
        
        let newObjects: [CloudableObject] = [newBattleShip, newArmor, steve, newSarah, lucus, newGundam]
        let newRecords = newObjects.map { ObjectConverter().convert($0) }
        
        changeManager.handleSyncronizationGet(modification: newRecords, deletion: recordIDToBeDeleted)
        
        // Assertion
        
        let ships = realm.objects(BattleShip.self)
        let armors = realm.objects(MobileArmor.self)
        let suits = realm.objects(MobileSuit.self)
        XCTAssert(pilots.count == 4)
        XCTAssert(sarah.age == 17)
        XCTAssert(tim.isInvalidated)
        XCTAssert(armors.count == 2)
        XCTAssert(suits.count == 1)
        
        let addedBattleShip: BattleShip! = ships.filter({ $0.name == "NewShip" }).first
        XCTAssertNotNil(addedBattleShip)
        XCTAssertEqual(addedBattleShip.msCatapults, 3)
        
        // Relationship things starts from here
        
        let addedGundam: MobileSuit! = addedBattleShip.mobileSuits.first
        XCTAssertNotNil(addedGundam)
        XCTAssertEqual(addedGundam.type, "MMM")
        let addedGundamPilot: Pilot! = addedGundam.pilot
        XCTAssertNotNil(addedGundamPilot)
        XCTAssertEqual(addedGundamPilot.name, "Sarah")
        let addedArmor: MobileArmor! = addedBattleShip.mobileArmors.first
        XCTAssertNotNil(addedArmor)
        XCTAssertEqual(addedArmor.type, "BBB")
        let addedArmorPilots = addedArmor.pilots
        XCTAssertEqual(addedArmorPilots.count, 1)
    }
    
    func testGenerateAndFinishUpload() {
        let realm = try! Realm()
        let tim = Pilot(name: "Tim", age: 21)
        let timID = tim.id
        let john = Pilot(name: "John", age: 24)
        let sarah = Pilot(name: "Sarah", age: 30)
        
        let gundam = MobileSuit(type: "ZZZ", pilot: tim)
        let armor = MobileArmor(type: "AAA", numberOfPilotsNeeded: 2, pilots: [john, tim])
        
        let battleShip = BattleShip(name: "Ship", msCatapults: 4, mobileSuits: [gundam], mobileArmors: [armor])
        
        try? realm.write {
            realm.add(tim)
            realm.add(john)
            realm.add(sarah)
        }
        
        let changeManager = ChangeManager()
        changeManager.setupSyncedEntitiesIfNeeded()
        
        try? realm.write {
            realm.add(gundam)
            realm.add(armor)
            realm.add(battleShip)
            realm.delete(cloudableObject: tim)
        }
        
        wait(for: 3)
        
        let (modification, deletion) = changeManager.generateUploads()
        
        XCTAssertEqual(modification.count, 5)
        XCTAssertEqual(deletion.count, 1)
        XCTAssertEqual(deletion[0].recordName, timID)
        XCTAssertEqual(Set(modification.filter({$0.recordType == Pilot.recordType}).map({$0.recordID.recordName})),
                       Set([john.id, sarah.id]))
        
        changeManager.finishUploads(saved: modification, deleted: deletion)
        
        let deletedSyncedEntity: SyncedEntity! = realm.object(ofType: SyncedEntity.self, forPrimaryKey: timID)
        XCTAssertNotNil(deletedSyncedEntity)
        XCTAssert(deletedSyncedEntity.isDeleted)
        let allOtherEntities = realm.objects(SyncedEntity.self).filter { $0.identifier != timID }
        for s in allOtherEntities {
            XCTAssertEqual(s.changeState, .synced)
        }
    }
}

extension ChangeManagerTests {
    func wait(for duration: TimeInterval) {
        let waitExpectation = expectation(description: "Waiting")
        
        let when = DispatchTime.now() + duration
        DispatchQueue.main.asyncAfter(deadline: when) {
            waitExpectation.fulfill()
        }
        
        waitForExpectations(timeout: duration + 0.5)
    }
}
