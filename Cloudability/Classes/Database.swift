//
//  Database.swift
//  Cloudability
//
//  Created by Shangxin Guo on 2018/4/15.
//

import Foundation
import CloudKit
import PromiseKit

class Database {
    let ckDatabase: CKDatabase
    
    init(database: CKDatabase) {
        ckDatabase = database
    }
    
    func add(_ operation: CKDatabaseOperation) {
        ckDatabase.add(operation)
    }
    
    /// Fetches one record zone asynchronously from the current database.
    public func fetch(withRecordZoneID recordZoneID: CKRecordZone.ID) -> Promise<CKRecordZone> {
        return ckDatabase.fetch(withRecordZoneID: recordZoneID)
    }
    
    /// Fetches all record zones asynchronously from the current database.
    public func fetchAllRecordZones() -> Promise<[CKRecordZone]> {
        return ckDatabase.fetchAllRecordZones()
    }
    
    /// Saves one record zone asynchronously to the current database.
    public func save(_ record: CKRecord) -> Promise<CKRecord> {
        return ckDatabase.save(record)
    }
    
    /// Saves one record zone asynchronously to the current database.
    public func save(_ recordZone: CKRecordZone) -> Promise<CKRecordZone> {
        return ckDatabase.save(recordZone)
    }
    
    /// Delete one subscription object asynchronously from the current database.
    public func delete(withRecordID recordID: CKRecord.ID) -> Promise<CKRecord.ID> {
        return ckDatabase.delete(withRecordID: recordID)
    }
    
    /// Delete one subscription object asynchronously from the current database.
    public func delete(withRecordZoneID zoneID: CKRecordZone.ID) -> Promise<CKRecordZone.ID> {
        return ckDatabase.delete(withRecordZoneID: zoneID)
    }
    
    #if !os(watchOS)
    /// Fetches one record zone asynchronously from the current database.
    public func fetch(withSubscriptionID subscriptionID: String) -> Promise<CKSubscription> {
        return ckDatabase.fetch(withSubscriptionID: subscriptionID)
    }
    
    /// Fetches all subscription objects asynchronously from the current database.
    public func fetchAllSubscriptions() -> Promise<[CKSubscription]> {
        return ckDatabase.fetchAllSubscriptions()
    }
    
    /// Saves one subscription object asynchronously to the current database.
    public func save(_ subscription: CKSubscription) -> Promise<CKSubscription> {
        return ckDatabase.save(subscription)
    }
    
    /// Delete one subscription object asynchronously from the current database.
    public func delete(withSubscriptionID subscriptionID: String) -> Promise<String> {
        return ckDatabase.delete(withSubscriptionID: subscriptionID)
    }
    #endif
    
    func addDatabaseSubscription(subscriptionID: String, operationQueue: OperationQueue? = nil,
                                 completionHandler: @escaping (NSError?) -> Void) {
        
        let subscription = CKDatabaseSubscription(subscriptionID: subscriptionID)
        
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        
        subscription.notificationInfo = notificationInfo
        
        let operation = CKModifySubscriptionsOperation(subscriptionsToSave: [subscription], subscriptionIDsToDelete: nil)
        
        operation.modifySubscriptionsCompletionBlock = { _, _, error in
            completionHandler(error as NSError?)
        }
        
        if let operationQueue = operationQueue {
            operation.database = ckDatabase
            operationQueue.addOperation(operation)
        } else {
            add(operation)
        }
    }
}
