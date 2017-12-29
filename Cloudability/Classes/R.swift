//
//  ItemStore.swift
//  Cloudability
//
//  Created by Inti Guo on 11/10/2016.
//  Copyright © 2016 Inti Guo. All rights reserved.
//

import Foundation
import RealmSwift

internal func dPrint(_ item: @autoclosure () -> Any) {
    #if DEBUG
        print(item())
    #endif
}

typealias ID = String

/// Gloabal realm in main thread.
let r = R()

public extension Realm {
    
    ///Deletes an CloudableObject from the Realm.
    /// - Warning
    /// This method may only be called during a write transaction.
    func delete(cloudableObject: CloudableObject) {
        let id = cloudableObject.pkProperty
        delete(cloudableObject)
        guard let syncedEntity = object(ofType: SyncedEntity.self, forPrimaryKey: id)
            else { return }
        syncedEntity.changeState = .deleted
    }
    
    /// Write that starts transaction only when it's not in transaction.
    public func safeWrite(withoutNotifying tokens: [NotificationToken] = [], _ block: (() throws -> Void)) throws {
        if isInWriteTransaction {
            try block()
        } else {
            beginWrite()
            do { try block() }
            catch {
                if isInWriteTransaction { cancelWrite() }
                throw error
            }
            if isInWriteTransaction { try commitWrite(withoutNotifying: tokens) }
        }
    }
}

final class R {
    let configuration: Realm.Configuration
    
    /// A new `Realm` reference is generated on every get, to avoid a realm object to be used in different thread.
    /// Luckily Realm automatically handles `Realm` creation and will reuse when possible.
    var realm: Realm {
        if Thread.isMainThread { return _mainRealm }
        return try! Realm()
    }
    
    lazy var _mainRealm = { return try! Realm.init(configuration: Realm.Configuration.defaultConfiguration) }()
    
    func write(withoutNotifying tokens: [NotificationToken] = [], _ block: ((Realm) throws -> Void)) throws {
        do {
            let currentRealm = realm
            try currentRealm.safeWrite(withoutNotifying: tokens) {
                try block(currentRealm)
            }
        } catch let error {
            throw error
        }
    }
    
    init(configuration: Realm.Configuration = .defaultConfiguration) {
        self.configuration = configuration
    }
    
    func deleteSoftDeletedObjects() {
        
    }
}



