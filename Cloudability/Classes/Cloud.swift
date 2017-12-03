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

public enum CloudError: Error {
    case AlreadySyncing
    case ICloudAccountNotAvailable
}

public final class Cloud {
    fileprivate enum Defaults {
        static let changeTokenKey = "CloudabilityChangeToken"
        static let createdCustomZoneKey = "CloudabilityCreatedCustomZone"
        
        static var changeToken: CKServerChangeToken? {
            get {
                if let tokenData = UserDefaults.standard.data(forKey: changeTokenKey) {
                    return NSKeyedUnarchiver.unarchiveObject(with: tokenData) as? CKServerChangeToken
                }
                return nil
            }
            set {
                if let token = newValue {
                    UserDefaults.standard.set(NSKeyedArchiver.archivedData(withRootObject: token), forKey: changeTokenKey)
                }
            }
        }
        
        static var createdCustomZone: Bool {
            get { return UserDefaults.standard.bool(forKey: createdCustomZoneKey) }
            set { UserDefaults.standard.set(newValue, forKey: createdCustomZoneKey) }
        }
    }
    
    internal lazy var changeManager: ChangeManager = {
        let c = ChangeManager()
        c.cloud = self
        return c
    }()
    
    private(set) var syncing = false
    var cancelled = false
    
    let container: CKContainer
    let databases: (private: CKDatabase, shared: CKDatabase, public: CKDatabase)
    let zoneID: CKRecordZoneID
    let dispatchQueue = DispatchQueue.global(qos: .userInitiated)
    private(set) var customZone: CKRecordZone?
    
    public init(containerIdentifier: String, recordZoneID: CKRecordZoneID) {
        container = CKContainer(identifier: containerIdentifier)
        databases = (container.privateCloudDatabase, container.sharedCloudDatabase, container.publicCloudDatabase)
        zoneID = recordZoneID
        
        NotificationCenter.default.addObserver(self, selector: #selector(cleanUp), name: .UIApplicationWillTerminate, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Public

extension Cloud {
    /// Start syncronization
    public func syncronize() -> Promise<Void> {
        return Promise { fullfill, reject in
            guard !syncing else { throw CloudError.AlreadySyncing }
            
            print("Cloud >> Start syncronization.")
            syncing = true
            
            Promise(value: ()).then(on: dispatchQueue) {
                
                self.container.accountStatus()
                
            }.then { accountStatus in
                
                guard case .available = accountStatus else { throw CloudError.ICloudAccountNotAvailable }
                return self.setupCustomZoneIfNeeded()
                
            }.then {
                
                self.setupPushNotificationIfNeeded()
                
            }.then { Void -> Promise<Void> in
                
                if self.cancelled { throw NSError.cancelledError() }
                return self._syncronize()
                
            }.always {
                
                self.finish()
                
            }.catch { error in
                
                reject(error)
                
            }
        }
    }
    
    func setupCustomZoneIfNeeded() -> Promise<Void> {
        return Promise { fullfill, reject in
            if customZone != nil {
                fullfill(())
                return
            }
            
            Promise(value: ()).then(on: dispatchQueue) {
                self.databases.private.fetch(withRecordZoneID: self.zoneID)
            }.then { recordZone -> Void in
                print("Cloud >>>> Zone already created, will use it directly.")
                self.customZone = recordZone
                Defaults.createdCustomZone = true
                fullfill(())
            }.catch { _ in // sadly zone was not created
                print("Cloud >>>> Zone was not created, will create it now.")
                firstly {
                    self.databases.private.save(CKRecordZone(zoneID: self.zoneID))
                }.then { recordZone -> Void in
                    print("Cloud >>>> Zone was successfully created.")
                    self.customZone = recordZone
                }.catch { error in
                    print("Cloud >>>> Aborting Syncronization: Zone was not successfully created for some reasons, should try again later.")
                    reject(error)
                }
            }
        }
    }
    
    func setupPushNotificationIfNeeded() -> Promise<Void> {
        return Promise { fullfill, reject in
            
        }
    }
    
    @objc func cleanUp() {
        let deletedSyncedEntities = r.syncedEntities.filter("isDeleted == true")
        let appliedPendingRelationships = r.pendingRelationships.filter("isApplied == true")
        
        try? r.write { realm in
            realm.delete(deletedSyncedEntities)
            realm.delete(appliedPendingRelationships)
        }
        r.deleteSoftDeletedObjects()
    }
}

// MARK: - Private

extension Cloud {
    private func _syncronize() -> Promise<Void> {
        return Promise<Void> { [unowned self] fullfill, reject in
            Promise(value: ()).then(on: dispatchQueue) {
                () -> Promise<(toSave: [CKRecord], toDelete: [CKRecordID], lastChangeToken: CKServerChangeToken?)> in
                
                print("Cloud >> Fetch changes from private database.")
                
                return self.fetchChanges(from: self.databases.private)
                
            }.then { (modification, deletion, token) -> ([CKRecord], [CKRecordID]) in
                
                print("Cloud >> Send data to changeManager to save to disk.")
                
                try self.changeManager.handleSyncronizationGet(modification: modification, deletion: deletion)
                Defaults.changeToken = token
                
                print("Cloud >> Change saved, fetch upload data from changeManager.")
                
                let uploads = try self.changeManager.generateUploads()
                return (uploads.modification, uploads.deletion)
                
            }.then { (modification, deletion) -> Promise<(saved: [CKRecord]?, deleted: [CKRecordID]?)> in
                
                print("Cloud >> Push local changes to cloud.")
                
                return self.pushChanges(to: self.databases.private, saving: modification, deleting: deletion)
                
            }.then { saved, deleted -> Void in
                
                print("Cloud >> Upload finished.")
                
                try self.changeManager.finishUploads(saved: saved, deleted: deleted)
                
            }.always {
                
                print("Cloud >> Sync finished.")
                
                self.finish()
                
            }.catch { error in
                
                reject(error)
                
            }
        }
    }
    
    private func fetchChanges(from database: CKDatabase)
        -> Promise<(toSave: [CKRecord], toDelete: [CKRecordID], lastChangeToken: CKServerChangeToken?)> {
        return Promise { fullfill, reject in
            var recordsToSave = [CKRecord]()
            var recordsToDelete = [CKRecordID]()
            var lastChangeToken: CKServerChangeToken?
            
            let option = CKFetchRecordZoneChangesOptions()
            option.previousServerChangeToken = Defaults.changeToken
            let fetchOperation = CKFetchRecordZoneChangesOperation(recordZoneIDs: [zoneID], optionsByRecordZoneID: [zoneID: option])
            
            fetchOperation.recordChangedBlock = { record in
                recordsToSave.append(record)
            }
            
            fetchOperation.recordWithIDWasDeletedBlock = { id, token in
                recordsToDelete.append(id)
            }
            
            fetchOperation.recordZoneChangeTokensUpdatedBlock = { (zoneId, token, data) in
                lastChangeToken = token
            }
            
            fetchOperation.recordZoneFetchCompletionBlock = { (zoneId, changeToken, _, _, error) in
                if let error = error {
                    reject(error)
                    print("Cloud >>>> Error fetching zone changes for \(String(describing: Defaults.changeToken)) database.")
                    return
                }
                lastChangeToken = changeToken
            }
            
            fetchOperation.fetchRecordZoneChangesCompletionBlock = { error in
                if let error = error {
                    reject(error)
                    print("Cloud >>>> Error fetching zone changes for \(String(describing: Defaults.changeToken)) database.")
                    return
                }
                
                fullfill((recordsToSave, recordsToDelete, lastChangeToken))
            }
            
            fetchOperation.qualityOfService = .userInitiated
            
            database.add(fetchOperation)
        }
    }
    
    private func pushChanges(to database: CKDatabase, saving save: [CKRecord], deleting deletion: [CKRecordID])
        -> Promise<(saved: [CKRecord]?, deleted: [CKRecordID]?)> {
        return Promise { fullfill, reject in
            let operation = CKModifyRecordsOperation(recordsToSave: save, recordIDsToDelete: deletion)
            
            operation.modifyRecordsCompletionBlock = { saved, deleted, error in
                if let error = (error as? CKError),
                    case .partialFailure = error.code {
                        print("Cloud >>>> Only apart of uploads are successfully applied to cloud.")
                }
                fullfill((saved, deleted))
            }
            
            database.add(operation)
        }
    }
    
    private func finish() {
        syncing = false
    }
    
    
}


