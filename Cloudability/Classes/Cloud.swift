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
    public static let databaseDidChangeRemotely = Notification.Name(rawValue: "databaseDidChangeRemotely")
}

public enum CloudError: Error {
    case AlreadySyncing
    case ICloudAccountNotAvailable
    case ZonesNotCreated
}

public final class Cloud {
    internal let changeManager: ChangeManager
    
    private(set) var syncing = false
    var cancelled = false
    
    let container: CKContainer
    let databases: (private: CKDatabase, shared: CKDatabase, public: CKDatabase)
    let dispatchQueue = DispatchQueue(label: "com.intii.Cloudability.Cloud", qos: .utility)
    
    public init(containerIdentifier: String? = nil) {
        container = containerIdentifier == nil ? CKContainer.default() : CKContainer(identifier: containerIdentifier!)
        databases = (container.privateCloudDatabase, container.sharedCloudDatabase, container.publicCloudDatabase)
        changeManager = ChangeManager()
        changeManager.cloud = self
        changeManager.setupSyncedEntitiesIfNeeded()
        setupPushNotificationIfNeeded()
        NotificationCenter.default.addObserver(self, selector: #selector(cleanUp), name: .UIApplicationWillTerminate, object: nil)
        
        try? pull() // syncronize at launch
        
        resumeLongLivedOperationsIfPossible()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Public

extension Cloud {
    
    /// Start syncronization
    public func pull() throws {
        dPrint("Cloud >> Start pull.")
        
        Promise(value: ()).then(on: dispatchQueue) { [weak self] Void -> Promise<CKAccountStatus> in
            
            guard let ego = self else { throw NSError.cancelledError() }
            return ego.container.accountStatus()
            
        }.then { [weak self] accountStatus -> Promise<Void> in
            
            guard let ego = self else { throw NSError.cancelledError() }
            guard case .available = accountStatus else { throw CloudError.ICloudAccountNotAvailable }
            return ego.setupCustomZoneIfNeeded()
            
        }.then { [weak self] Void -> Promise<Void> in
            
            guard let ego = self else { throw NSError.cancelledError() }
            return ego.getChangesFromCloud()
            
        }.always {
                
            dPrint("Cloud >> Syncronization finished.")
                
        }.catch { error in
            print("Cloud >x \(error.localizedDescription)")
        }
    }
    
    func push(modification: [CKRecord], deletion: [CKRecordID]) throws {
        dPrint("Cloud >> Start push.")
        
        Promise(value: ()).then(on: dispatchQueue) { [weak self] Void -> Promise<CKAccountStatus> in
            
            guard let ego = self else { throw NSError.cancelledError() }
            return ego.container.accountStatus()
            
        }.then { [weak self] accountStatus -> Promise<Void> in
                
            guard let ego = self else { throw NSError.cancelledError() }
            guard case .available = accountStatus else { throw CloudError.ICloudAccountNotAvailable }
            return ego.setupCustomZoneIfNeeded()
                
        }.then { [weak self] Void -> Promise<Void>? in
            
            self?.pushChangesOntoCloud(modification: modification, deletion: deletion)
                
        }.always {
                
            dPrint("Cloud >> Syncronization finished.")
                
        }.catch { error in
            
        }
    }
    
    func setupCustomZoneIfNeeded() -> Promise<Void> {
        return Promise { fullfill, reject in
            
            Promise(value: ()).then(on: dispatchQueue) {
                self.databases.private.fetchAllRecordZones()
            }.then { recordZones -> Void in
                guard recordZones.count == self.changeManager.allZoneIDs.count
                    else { throw CloudError.ZonesNotCreated }
                dPrint("Cloud >> Zones already created, will use them directly.")
                Defaults.createdCustomZone = true
                fullfill(())
            }.catch { error in // sadly zone was not created
                if error == CloudError.ZonesNotCreated {
                    dPrint("Cloud >> Zones were not created, will create them now.")
                    let zoneCreationPromises = self.changeManager.allZoneIDs.map {
                        return self.databases.private.save(CKRecordZone(zoneID: $0))
                    }
                    when(fulfilled: zoneCreationPromises).then { recordZone -> Void in
                        dPrint("Cloud >> Zones were successfully created.")
                        Defaults.createdCustomZone = true
                        fullfill(())
                    }.catch { error in
                        print("Cloud >> Aborting Syncronization: Zone was not successfully created for some reasons, should try again later.")
                        reject(error)
                    }
                } else {
                    print("Cloud >> \(error.localizedDescription)")
                    reject(error)
                }
            }
        }
    }
    
    func setupPushNotificationIfNeeded() {
        NotificationCenter.default.addObserver(
            forName: .databaseDidChangeRemotely,
            object: nil,
            queue: OperationQueue.main,
            using: { [weak self] _ in
                dPrint("Cloud >> Recieved push notification for database change.")
                guard let ego = self else { return }
                try? ego.pull()
            })
    }
    
    @objc func cleanUp() {
        changeManager.cleanUp()
    }
    
}

// MARK: - Private

extension Cloud {
    private func getChangesFromCloud() -> Promise<Void> {
        return Promise<Void> { [unowned self] fullfill, reject in
            Promise(value: ()).then(on: dispatchQueue) {

                self.fetchChangesInDatabase()
                
            }.then { zoneIDs in
                
                self.fetchChanges(from: zoneIDs, in: self.databases.private)
                
            }.then { (modification, deletion, tokens) -> Void in
                
                self.changeManager.handleSyncronizationGet(modification: modification, deletion: deletion)
                for (id, token) in tokens {
                    Defaults.setZoneChangeToken(to: token, forZoneID: id)
                }
                fullfill(())
                
            }.catch { error in
                print("Cloud >> \(error.localizedDescription)")
                reject(error)
                
            }
        }
    }
    
    private func pushChangesOntoCloud(modification: [CKRecord], deletion: [CKRecordID]) -> Promise<Void> {
        return Promise<Void> { [weak self] fullfill, reject in
            
            Promise(value: ()).then(on: dispatchQueue) {
                () -> Promise<(saved: [CKRecord]?, deleted: [CKRecordID]?)> in
                
                dPrint("Cloud >> Push local changes to cloud.")
                guard let ego = self else { throw NSError.cancelledError() }
                
                return ego.pushChanges(to: ego.databases.private, saving: modification, deleting: deletion)
                
            }.then { saved, deleted -> Void in
                    
                dPrint("Cloud >> Upload finished.")
                guard let ego = self else { throw NSError.cancelledError() }
                
                ego.changeManager.finishUploads(saved: saved, deleted: deleted)
                fullfill(())
                    
            }.catch { error in
                    
                reject(error)
            }
        }
    }
    
    private func fetchChangesInDatabase() -> Promise<[CKRecordZoneID]> {
        return Promise { fullfill, reject in
            dPrint("Cloud >> Fetch changes in private database.")
            
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
                        try? self?.pull()
                    }
                    reject(error)
                    return
                }
                
                Defaults.serverChangeToken = token
                fullfill(zoneIDs)
            }
            
            operation.qualityOfService = .utility
            databases.private.add(operation)
        }
    }
    
    private func fetchChanges(from zoneIDs: [CKRecordZoneID], in database: CKDatabase)
        -> Promise<(toSave: [CKRecord], toDelete: [CKRecordID], lastChangeToken: [CKRecordZoneID : CKServerChangeToken])> {
        return Promise { fullfill, reject in
            
            dPrint("Cloud >> Fetch zone changes from private database.")
            
            guard !zoneIDs.isEmpty else { fullfill(([], [], [:])); return }
            
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
                    reject(error)
                    dPrint("Cloud >>>> Error fetching zone changes for \(String(describing: Defaults.serverChangeToken)) database.")
                    return
                }
                lastChangeTokens[zoneID] = changeToken
            }
            
            operation.fetchRecordZoneChangesCompletionBlock = { [weak self] error in
                if let error = error {
                    self?.retryOperationIfPossible(with: error) {
                        try? self?.pull()
                    }
                    reject(error)
                    return
                }
                
                fullfill((recordsToSave, recordsToDelete, lastChangeTokens))
            }
            
            operation.qualityOfService = .utility
            database.add(operation)
        }
    }
    
    private func pushChanges(to database: CKDatabase, saving save: [CKRecord], deleting deletion: [CKRecordID])
        -> Promise<(saved: [CKRecord]?, deleted: [CKRecordID]?)> {
        return Promise { fullfill, reject in
            let operation = CKModifyRecordsOperation(recordsToSave: save, recordIDsToDelete: deletion)
            operation.isLongLived = true
            operation.savePolicy = .changedKeys
            operation.modifyRecordsCompletionBlock = { [weak self] saved, deleted, error in
                if let error = error {
                    self?.retryOperationIfPossible(with: error) {
                        try? self?.push(modification: save, deletion: deletion)
                    }
                    reject(error)
                    return
                }
                
                fullfill((saved, deleted))
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
                            dPrint("Cloud >> Resume modify records operation success!")
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
            let delay = DispatchTime.now() + retryAfter
            DispatchQueue.main.asyncAfter(deadline: delay, execute: block)
        default: break
        }
    }
}

// MARK: - Persistent

extension Cloud {
    fileprivate enum Defaults {
        static let serverChangeTokenKey = "cloudability_server_change_token"
        static let createdCustomZoneKey = "cloudability_created_custom_zone"
        static let zoneChangeTokenKeyPrefix = "cloudability_zone_change_token_"
        
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
    }
}


