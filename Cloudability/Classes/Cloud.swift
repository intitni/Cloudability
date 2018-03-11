//
//  Cloud.swift
//  BestBefore
//
//  Created by Shangxin Guo on 23/10/2017.
//  Copyright © 2017 Inti Guo. All rights reserved.
//

import Foundation
import CloudKit
import PromiseKit
import RealmSwift

public extension Notification.Name {
    /// You should listen to this one
    public static let iCloudAccountNotAvailable = Notification.Name(rawValue: "iCloudAccountNotAvailable")
}

public enum CloudError: Error {
    case alreadySyncing
    case iCloudAccountNotAvailable
    case zonesNotCreated
    case cancel
}

public enum ZoneType {
    /// Use the defualtZone.
    case defaultZone
    /// Use mutiple zones for each record type.
    case individualForEachRecordType
    /// Use 1 custom zone for all record types.
    case sameZone(String)
    /// Provide a rule that returns a zone ID for each type.
    case customRule((CloudableObject.Type) -> CKRecordZoneID)
}

public final class Cloud {
    internal let changeManager: ChangeManager
    
    private(set) public var enabled: Bool = false
    
    private(set) var syncing = false
    var cancelled = false
    
    let container: CKContainer
    let databases: (private: CKDatabase, shared: CKDatabase, public: CKDatabase)
    let dispatchQueue = DispatchQueue(label: "com.intii.Cloudability.Cloud", qos: .utility)
    
    var finishBlock: ()->Void = {}
    
    public init(containerIdentifier: String? = nil, zoneType: ZoneType = .defaultZone, finishBlock: @escaping ()->Void = {}) {
        container = containerIdentifier == nil ? CKContainer.default() : CKContainer(identifier: containerIdentifier!)
        databases = (container.privateCloudDatabase, container.sharedCloudDatabase, container.publicCloudDatabase)
        changeManager = ChangeManager(zoneType: zoneType)
        self.finishBlock = finishBlock
        changeManager.cloud = self
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    public func switchOn() {
        guard !enabled else { return }
        enabled = true
        changeManager.setupSyncedEntitiesIfNeeded()
        subscribeToDatabaseChangesIfNeeded()
        NotificationCenter.default.addObserver(self, selector: #selector(cleanUp), name: .UIApplicationWillTerminate, object: nil)
        
        pull { [weak self] in guard $0 else { return }; self?.push() } // syncronize at launch
        
        resumeLongLivedOperationsIfPossible()
    }
    
    public func switchOff() {
        guard enabled else { return }
        enabled = false
    }
}

// MARK: - Public

extension Cloud {
    
    /// Start pull
    public func pull(_ completionHandler: @escaping (Bool)->Void = { _ in }) {
        log("Cloud >> Start pull.")
        
        Promise().then(on: dispatchQueue) { [weak self] Void -> Promise<CKAccountStatus> in
            
            guard let ego = self else { throw CloudError.cancel }
            return ego.container.accountStatus()
            
        }.then { [weak self] accountStatus -> Promise<Void> in
            
            guard let ego = self else { throw CloudError.cancel }
            guard case .available = accountStatus else { throw CloudError.iCloudAccountNotAvailable }
            return ego.setupCustomZoneIfNeeded()
            
        }.then { [weak self] Void -> Promise<Void> in
            
            guard let ego = self else { throw CloudError.cancel }
            return ego.getChangesFromCloud()
            
        }.done {
            
            completionHandler(true)
            
        }.ensure(on: DispatchQueue.main) { [weak self] in
            
            self?.finishBlock()
            log("Cloud >> Pull finished.")
                
        }.catch { [weak self] error in
            
            logError("Cloud >x \(error.localizedDescription)")
            self?.handlePushAndPullError(error: error)
            completionHandler(false)
        }
    }
    
    /// Start push
    public func push(_ completionHandler: @escaping (Bool)->Void = { _ in }) {
        let uploads = changeManager.generateUploads()
        push(modification: uploads.modification, deletion: uploads.deletion, completionHandler: completionHandler)
    }
}

// MARK: - Internal

extension Cloud {
    func push(modification: [CKRecord], deletion: [CKRecordID], completionHandler: @escaping (Bool)->Void = { _ in }) {
        log("Cloud >> Start push.")
        
        Promise().then(on: dispatchQueue) { [weak self] Void -> Promise<CKAccountStatus> in
            
            guard let ego = self else { throw CloudError.cancel }
            return ego.container.accountStatus()
            
        }.then { [weak self] accountStatus -> Promise<Void> in
            
            guard let ego = self else { throw CloudError.cancel }
            guard case .available = accountStatus else { throw CloudError.iCloudAccountNotAvailable }
            return ego.setupCustomZoneIfNeeded()
            
        }.then { [weak self] _ -> Promise<Void> in
            
            guard let ego = self else { throw CloudError.cancel }
            return ego.pushChangesOntoCloud(modification: modification, deletion: deletion)
            
        }.done {
            
            completionHandler(true)
            
        }.ensure {
            
            log("Cloud >> Push finished.")
            
        }.catch { [weak self] error in
            
            logError("Cloud >x \(error.localizedDescription)")
            self?.handlePushAndPullError(error: error)
            completionHandler(false)
        }
    }
    
    func setupCustomZoneIfNeeded() -> Promise<Void> {
        return Promise { seal in
            
            Promise().then(on: dispatchQueue) {
                
                self.databases.private.fetchAllRecordZones()
                
            }.done { recordZones in
                    
                guard recordZones.count == self.changeManager.allZoneIDs.count + 1
                    else { throw CloudError.zonesNotCreated }
                log("Cloud >> Zones already created, will use them directly.")
                Defaults.createdCustomZone = true
                seal.fulfill(())
                    
            }.catch { error in // sadly zone was not created
                    
                if error == CloudError.zonesNotCreated {
                    log("Cloud >> Zones were not created, will create them now.")
                    let zoneCreationPromises = self.changeManager.allZoneIDs.map {
                        return self.databases.private.save(CKRecordZone(zoneID: $0))
                    }
                    when(fulfilled: zoneCreationPromises).done { recordZone in
                        log("Cloud >> Zones were successfully created.")
                        Defaults.createdCustomZone = true
                        seal.fulfill(())
                        }.catch { error in
                            logError("Cloud >x Aborting Syncronization: Zone was not successfully created for some reasons, should try again later.")
                            seal.reject(error)
                    }
                } else {
                    logError("Cloud >x \(error.localizedDescription)")
                    seal.reject(error)
                }
            }
        }
    }
    
    @objc func cleanUp() {
        changeManager.cleanUp()
    }
}

// MARK: - Private

extension Cloud {
    private func getChangesFromCloud() -> Promise<Void> {
        return Promise { [unowned self] seal in
            Promise().then(on: dispatchQueue) {

                self.fetchChangesInDatabase()
                
            }.then { zoneIDs in
                
                self.fetchChanges(from: zoneIDs, in: self.databases.private)
                
            }.done {
                let (modification, deletion, tokens) = $0
                self.changeManager.handleSyncronizationGet(modification: modification, deletion: deletion)
                for (id, token) in tokens {
                    Defaults.setZoneChangeToken(to: token, forZoneID: id)
                }
                seal.fulfill(())
                
            }.catch { error in
                logError("Cloud >x \(error.localizedDescription)")
                seal.reject(error)
                
            }
        }
    }
    
    private func pushChangesOntoCloud(modification: [CKRecord], deletion: [CKRecordID]) -> Promise<Void> {
        return Promise { [weak self] seal in
            
            Promise().then(on: dispatchQueue) {
                () -> Promise<(saved: [CKRecord]?, deleted: [CKRecordID]?)> in
                
                log("Cloud >> Push local changes to cloud.")
                guard let ego = self else { throw CloudError.cancel }
                
                return ego.pushChanges(to: ego.databases.private, saving: modification, deleting: deletion)
                
            }.done { saved, deleted in
                    
                log("Cloud >> Upload finished.")
                guard let ego = self else { throw CloudError.cancel }
                
                ego.changeManager.finishUploads(saved: saved, deleted: deleted)
                seal.fulfill(())
                    
            }.catch { error in
                logError(error.localizedDescription)
                seal.reject(error)
            }
        }
    }
    
    private func fetchChangesInDatabase() -> Promise<[CKRecordZoneID]> {
        return Promise { seal in
            log("Cloud >> Fetch changes in private database.")
            
            var zoneIDs = [CKRecordZoneID]()
            
            let operation = CKFetchDatabaseChangesOperation(previousServerChangeToken: Defaults.serverChangeToken)
            operation.fetchAllChanges = true

//            operation.changeTokenUpdatedBlock = { token in
//                Defaults.serverChangeToken = token
//            }
            
            operation.recordZoneWithIDChangedBlock = { zoneID in
                zoneIDs.append(zoneID)
            }
            
            operation.fetchDatabaseChangesCompletionBlock = { [weak self] token, _, error in
                if let error = error {
                    self?.retryOperationIfPossible(with: error) {
                        self?.pull()
                    }
                    seal.reject(error)
                    return
                }
                
                Defaults.serverChangeToken = token
                seal.fulfill(zoneIDs)
            }
            
            operation.qualityOfService = .utility
            databases.private.add(operation)
        }
    }
    
    private func fetchChanges(from zoneIDs: [CKRecordZoneID], in database: CKDatabase)
        -> Promise<(toSave: [CKRecord], toDelete: [CKRecordID], lastChangeToken: [CKRecordZoneID : CKServerChangeToken])> {
        return Promise { seal in
            
            log("Cloud >> Fetch zone changes from private database.")
            
            guard !zoneIDs.isEmpty else { seal.fulfill(([], [], [:])); return }
            
            var recordsToSave = [CKRecord]()
            var recordsToDelete = [CKRecordID]()
            var lastChangeTokens = [CKRecordZoneID: CKServerChangeToken]()
            
            let operation = CKFetchRecordZoneChangesOperation(
                recordZoneIDs: zoneIDs,
                optionsByRecordZoneID: zoneIDs.reduce(into: [CKRecordZoneID:CKFetchRecordZoneChangesOptions](), {
                    result, zoneID in
                    let option = CKFetchRecordZoneChangesOptions()
                    option.previousServerChangeToken = Defaults.zoneChangeToken(forZoneName: zoneID.zoneName)
                    result[zoneID] = option
                }))
            
            operation.fetchAllChanges = true
            
            operation.recordChangedBlock = { record in
                recordsToSave.append(record)
            }
            
            operation.recordWithIDWasDeletedBlock = { id, _ in
                recordsToDelete.append(id)
            }
            
            operation.recordZoneChangeTokensUpdatedBlock = { (zoneID, token, data) in
                lastChangeTokens[zoneID] = token
            }
            
            operation.recordZoneFetchCompletionBlock = { (zoneID, changeToken, _, _, error) in
                if let error = error {
                    seal.reject(error)
                    logError("Cloud >>>> Error fetching zone changes for \(String(describing: Defaults.serverChangeToken)) database.")
                    return
                }
                lastChangeTokens[zoneID] = changeToken
            }
            
            operation.fetchRecordZoneChangesCompletionBlock = { [weak self] error in
                if let error = error {
                    self?.retryOperationIfPossible(with: error) {
                        self?.pull()
                    }
                    seal.reject(error)
                    return
                }
                
                seal.fulfill((recordsToSave, recordsToDelete, lastChangeTokens))
            }
            
            operation.qualityOfService = .utility
            database.add(operation)
        }
    }
    
    private func subscribeToDatabaseChangesIfNeeded() {
        log("Cloud >> Subscribe to database changes.")
        
        func createDatabaseSubscriptionOperation(subscriptionId: String) -> CKModifySubscriptionsOperation {
            let subscription = CKDatabaseSubscription(subscriptionID: subscriptionId)
            let notificationInfo = CKNotificationInfo()
            
            // send a silent notification
            notificationInfo.shouldSendContentAvailable = true
            subscription.notificationInfo = notificationInfo
            let operation = CKModifySubscriptionsOperation(subscriptionsToSave: [subscription], subscriptionIDsToDelete: [])
            operation.qualityOfService = .utility
            
            return operation
        }
        
        if !Defaults.subscribedToPrivateDatabase {
            let createSubscriptionOperation = createDatabaseSubscriptionOperation(subscriptionId: "private")
            createSubscriptionOperation.modifySubscriptionsCompletionBlock = { [weak self] (subscriptions, deletedIds, error) in
                if error == nil {
                    Defaults.subscribedToPrivateDatabase = true
                    log("Cloud >> Successfully subscribed to private database.")
                    return
                }
                log("Cloud >x Failed to subscribe to private database, may retry later. \(error?.localizedDescription ?? "")")
                self?.retryOperationIfPossible(with: error) {
                    self?.subscribeToDatabaseChangesIfNeeded()
                }
            }
            databases.private.add(createSubscriptionOperation)
        }
        
        if !Defaults.subscribedToPublicDatabase {
            let createSubscriptionOperation = createDatabaseSubscriptionOperation(subscriptionId: "public")
            createSubscriptionOperation.modifySubscriptionsCompletionBlock = { [weak self] (subscriptions, deletedIds, error) in
                if error == nil {
                    Defaults.subscribedToPublicDatabase = true
                    log("Cloud >> Successfully subscribed to public database.")
                    return
                }
                log("Cloud >x Failed to subscribe to public database, may retry later. \(error?.localizedDescription ?? "")")
                self?.retryOperationIfPossible(with: error) {
                    self?.subscribeToDatabaseChangesIfNeeded()
                }
            }
            databases.public.add(createSubscriptionOperation)
        }
        
        if !Defaults.subscribedToSharedDatabase {
            let createSubscriptionOperation = createDatabaseSubscriptionOperation(subscriptionId: "shared")
            createSubscriptionOperation.modifySubscriptionsCompletionBlock = { [weak self] (subscriptions, deletedIds, error) in
                if error == nil {
                    Defaults.subscribedToSharedDatabase = true
                    log("Cloud >> Successfully subscribed to shared database.")
                    return
                }
                log("Cloud >x Failed to subscribe to shared database, may retry later. \(error?.localizedDescription ?? "")")
                self?.retryOperationIfPossible(with: error) {
                    self?.subscribeToDatabaseChangesIfNeeded()
                }
            }
            databases.shared.add(createSubscriptionOperation)
        }
    }
    
    private func pushChanges(to database: CKDatabase, saving save: [CKRecord], deleting deletion: [CKRecordID])
        -> Promise<(saved: [CKRecord]?, deleted: [CKRecordID]?)> {
        return Promise { seal in
            let operation = CKModifyRecordsOperation(recordsToSave: save, recordIDsToDelete: deletion)
            operation.isLongLived = true
            operation.savePolicy = .changedKeys
            operation.modifyRecordsCompletionBlock = { [weak self] saved, deleted, error in
                if let error = error {
                    self?.retryOperationIfPossible(with: error) {
                        self?.push(modification: save, deletion: deletion)
                    }
                    seal.reject(error)
                    return
                }
                
                seal.fulfill((saved, deleted))
            }
            
            operation.qualityOfService = .utility
            database.add(operation)
        }
    }
    
    private func resumeLongLivedOperationsIfPossible() {
        container.fetchAllLongLivedOperationIDs { [weak self] operationIDs, error in
            guard error == nil else { return }
            guard let operationIDs = operationIDs else { return }
            for id in operationIDs {
                self?.container.fetchLongLivedOperation(withID: id, completionHandler: { operation, error in
                    guard error == nil else { return }
                    if let operation = operation as? CKModifyRecordsOperation {
                        operation.modifyRecordsCompletionBlock = { (_,_,_) in
                            log("Cloud >> Resume modify records operation success!")
                        }
                        self?.container.add(operation)
                    }
                })
            }
        }
    }
    
    private func retryOperationIfPossible(with error: Error?, block: @escaping () -> Void) {
        guard let error = error as? CKError else { return }
        switch error.code {
        case .zoneBusy, .serviceUnavailable, .requestRateLimited:
            guard let retryAfter = error.userInfo[CKErrorRetryAfterKey] as? Double else { break }
            log("Cloud >> Retry after \(retryAfter)s.")
            let delay = DispatchTime.now() + retryAfter
            DispatchQueue.main.asyncAfter(deadline: delay, execute: block)
        default:
            log("Cloud >> Unable to retry this operation.")
        }
    }
    
    private func handlePushAndPullError(error: Error) {
        switch error {
        case CloudError.iCloudAccountNotAvailable:
            NotificationCenter.default.post(Notification(name: .iCloudAccountNotAvailable))
        default: break
        }
    }
}

// MARK: - Persistent

extension Cloud {
    fileprivate enum Defaults {
        private static let serverChangeTokenKey = "cloudability_server_change_token"
        private static let createdCustomZoneKey = "cloudability_created_custom_zone"
        private static let subscribedToPrivateDatabaseKey = "subscribed_to_private_database"
        private static let subscribedToPublicDatabaseKey = "subscribed_to_public_database"
        private static let subscribedToSharedDatabaseKey = "subscribed_to_shared_database"
        private static let zoneChangeTokenKeyPrefix = "cloudability_zone_change_token_"
        
        static func zoneChangeTokenKey(zoneName suffix: String) -> String {
            return zoneChangeTokenKeyPrefix + suffix
        }
        
        static var serverChangeToken: CKServerChangeToken? {
            get {
                if let tokenData = UserDefaults.standard.data(forKey: serverChangeTokenKey) {
                    return NSKeyedUnarchiver.unarchiveObject(with: tokenData) as? CKServerChangeToken
                }
                return nil
            }
            set {
                if let token = newValue {
                    UserDefaults.standard.set(NSKeyedArchiver.archivedData(withRootObject: token), forKey: serverChangeTokenKey)
                }
            }
        }
        
        static func zoneChangeToken(forZoneName name: String) -> CKServerChangeToken? {
            if let tokenData = UserDefaults.standard.data(forKey: zoneChangeTokenKey(zoneName: name)) {
                return NSKeyedUnarchiver.unarchiveObject(with: tokenData) as? CKServerChangeToken
            }
            return nil
        }
        
        static func setZoneChangeToken(to token: CKServerChangeToken?, forZoneName name: String) {
            if let token = token {
                UserDefaults.standard.set(NSKeyedArchiver.archivedData(withRootObject: token), forKey: zoneChangeTokenKey(zoneName: name))
            }
        }
        
        static func zoneChangeToken(forZoneID zoneID: CKRecordZoneID) -> CKServerChangeToken? {
            return zoneChangeToken(forZoneName: zoneID.zoneName)
        }
        
        static func setZoneChangeToken(to token: CKServerChangeToken?, forZoneID zoneID: CKRecordZoneID) {
            setZoneChangeToken(to: token, forZoneName: zoneID.zoneName)
        }
        
        static var createdCustomZone: Bool {
            get { return UserDefaults.standard.bool(forKey: createdCustomZoneKey) }
            set { UserDefaults.standard.set(newValue, forKey: createdCustomZoneKey) }
        }
        
        static var subscribedToPrivateDatabase: Bool {
            get { return UserDefaults.standard.bool(forKey: subscribedToPrivateDatabaseKey) }
            set { UserDefaults.standard.set(newValue, forKey: subscribedToPrivateDatabaseKey) }
        }
        
        static var subscribedToSharedDatabase: Bool {
            get { return UserDefaults.standard.bool(forKey: subscribedToSharedDatabaseKey) }
            set { UserDefaults.standard.set(newValue, forKey: subscribedToSharedDatabaseKey) }
        }
        
        static var subscribedToPublicDatabase: Bool {
            get { return UserDefaults.standard.bool(forKey: subscribedToPublicDatabaseKey) }
            set { UserDefaults.standard.set(newValue, forKey: subscribedToPublicDatabaseKey) }
        }
    }
}


