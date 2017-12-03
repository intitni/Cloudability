//
//  ItemStore.swift
//  Cloudability
//
//  Created by Inti Guo on 11/10/2016.
//  Copyright © 2016 Inti Guo. All rights reserved.
//

import Foundation
import RealmSwift

typealias ID = String

/// Gloabal realm in main thread.
let realm = try! Realm()
let store = ItemStore()

final class ItemStore {
    let configuration: Realm.Configuration
    
    /// A new `Realm` reference is generated on every get, to avoid a realm object to be used in different thread.
    /// Luckily Realm automatically handles `Realm` creation and will reuse when possible.
    var realm: Realm {
        if Thread.isMainThread { return _mainRealm }
        return try! Realm()
    }
    
    lazy var _mainRealm = { return try! Realm.init(configuration: Realm.Configuration.defaultConfiguration) }()
    
    func write(_ block: ((Realm) throws -> Void)) throws {
        do {
            let currentRealm = realm
            try currentRealm.write {
                try block(currentRealm)
            }
        } catch let error {
            throw error
        }
    }
    
    init(configuration: Realm.Configuration = .defaultConfiguration) {
        self.configuration = configuration
    }
}



