////
////  ObjectConverterTests.swift
////  BestBeforeTest
////
////  Created by Shangxin Guo on 13/11/2017.
////  Copyright © 2017 Inti Guo. All rights reserved.
////
//
//import XCTest
//import RealmSwift
//import CloudKit
//import UserNotifications
//import Cloudability
//
//class ObjectConverterTests: XCTestCase {
//
//    override func setUp() {
//        super.setUp()
//        Realm.Configuration.defaultConfiguration.inMemoryIdentifier = self.name
//    }
//
//    override func tearDown() {
//        try! store.write { realm in
//            realm.deleteAll()
//        }
//        if #available(iOS 10.0, *) {
//            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
//        } else {
//            UIApplication.shared.cancelAllLocalNotifications()
//        }
//
//        super.tearDown()
//    }
//
//    func testObjectToRecord() {
//        let inStockStrategy: InStockStrategy = {
//            return $0
//        } ( InStockStrategy() )
//
//        let category: BB_Dev.Category = {
//            $0.name = "Food"
//            $0.color = 1
//            $0.inStockStrategy = inStockStrategy
//            return $0
//        } ( BB_Dev.Category() )
//
//        try? store.write { realm in
//            realm.add(inStockStrategy, update: true)
//            realm.add(category, update: true)
//        }
//
//        let itemKind: ItemKind = {
//            $0.name = "Kind"
//            return $0
//        } ( ItemKind() )
//
//        let item: Item = {
//            $0.bestBeforeDate = Date.today + 2.month
//            $0.threshold = 30
//            return $0
//        } ( Item() )
//
//        try? store.add(item, in: itemKind, inCategoryWithId: category.id)
//
//        let objectConverter = ObjectConverter()
//        let itemRecord = objectConverter.convert(item)
//        let kindRecord = objectConverter.convert(itemKind)
//        let categoryRecord = objectConverter.convert(category)
//
//        // asserting itemRecord
//
//        XCTAssert(itemRecord["bestBeforeDate"]!.date == item.bestBeforeDate)
//        XCTAssert(itemRecord["productionDate"]?.date == item.productionDate)
//        XCTAssert(itemRecord["threshold"]!.int == item.threshold)
//
//        // asserting kindRecord
//
//        XCTAssert(kindRecord["name"]!.string == itemKind.name)
//        let kind_items = kindRecord["items"]
//        XCTAssertNotNil(kind_items)
//        XCTAssertNotNil(kind_items!.list)
//        let kind_items_ids = kind_items!.list! as? [String]
//        XCTAssertNotNil(kind_items_ids)
//        XCTAssert(kind_items_ids! == [item.id])
//        XCTAssertNotNil(kindRecord["inStockStrategy"])
//
//        // asserting categoryRecord
//
//        XCTAssert(categoryRecord["name"]!.string! == category.name)
//        XCTAssert(categoryRecord["color"]!.int! == category.color)
//        XCTAssert(categoryRecord["inStockStrategy"]!.string! == inStockStrategy.id)
//        let category_kinds = categoryRecord["itemKinds"]
//        XCTAssertNotNil(category_kinds)
//        XCTAssertNotNil(category_kinds!.list)
//        let category_kinds_ids = category_kinds!.list! as? [String]
//        XCTAssertNotNil(category_kinds_ids)
//        XCTAssert(category_kinds_ids! == [itemKind.id])
//    }
//
//    func testRecordToObject() {
//        let inStockStrategy: InStockStrategy = {
//            return $0
//        } ( InStockStrategy() )
//
//        try? store.write { realm in
//            realm.add(inStockStrategy, update: true)
//        }
//
//        let objectConverter = ObjectConverter()
//
//        let itemRecord: CKRecord = {
//            let r = CKRecord(recordType: "Item", recordID: CKRecordID(recordName: UUID().uuidString))
//            r["bestBeforeDate"] = Date.today + 20.day as NSDate
//            r["threshold"] = NSNumber(integerLiteral: 20)
//            return r
//        }()
//
//        let (item, _) = objectConverter.convert(itemRecord) as! (Item, [PendingRelationship])
//        try? store.write { realm in
//            realm.add(item, update: true)
//        }
//
//        XCTAssert(item.bestBeforeDate == Date.today + 20.day)
//        XCTAssert(item.threshold == 20)
//
//        let itemKindRecord: CKRecord = {
//            let r = CKRecord(recordType: "ItemKind", recordID: CKRecordID(recordName: UUID().uuidString))
//            r["items"] = [item.id] as NSArray
//            r["name"] = "Kind" as CKRecordValue
//            return r
//        }()
//
//        let (itemKind, p1) = objectConverter.convert(itemKindRecord) as! (ItemKind, [PendingRelationship])
//
//        let categoryRecord: CKRecord = {
//            let r = CKRecord(recordType: "Category", recordID: CKRecordID(recordName: UUID().uuidString))
//            r["inStockStrategy"] = inStockStrategy.id as CKRecordValue
//            r["name"] = "Category" as CKRecordValue
//            r["color"] = NSNumber(integerLiteral: 2)
//            r["itemKinds"] = [itemKind.id] as NSArray
//            return r
//        }()
//
//        let (category, p2) = objectConverter.convert(categoryRecord) as! (BB_Dev.Category, [PendingRelationship])
//
//        try? store.write { realm in
//            realm.add(itemKind, update: true)
//            realm.add(category, update: true)
//            realm.add(p1, update: true)
//            realm.add(p2, update: true)
//        }
//
//        store.applyPendingRelationships()
//
//        XCTAssert(itemKind.name == "Kind")
//        let ids_k = Array(itemKind.items.map{return $0.id})
//        XCTAssert(ids_k == [item.id], "\(ids_k)")
//
//        XCTAssert(category.name == "Category")
//        XCTAssert(category.color == 2)
//        XCTAssertNotNil(category.inStockStrategy)
//        XCTAssert(category.inStockStrategy!.id == inStockStrategy.id)
//        let ids_c = Array(category.itemKinds.map{return $0.id})
//        XCTAssert(ids_c == [itemKind.id], "\(ids_c)")
//    }
//}
//
