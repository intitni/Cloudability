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
}

public final class Cloud {
    internal let changeManager: ChangeManager
    
    private(set) var syncing = false
    var cancelled = false
    
    let container: CKContainer
    let databases: (private: CKDatabase, shared: CKDatabase, public: CKDatabase)
    let zoneID: CKRecordZoneID
    let dispatchQueue = DispatchQueue.global(qos: .utility)
    private(set) var customZone: CKRecordZone?
    
    public init(containerIdentifier: String, recordZoneID: CKRecordZoneID) {
        container = CKContainer(identifier: containerIdentifier)
        databases = (container.privateCloudDatabase, container.sharedCloudDatabase, container.publicCloudDatabase)
        zoneID = recordZoneID
        changeManager = ChangeManager()
        changeManager.cloud = self
        setupPushNotificationIfNeeded()
        NotificationCenter.default.addObserver(self, selector: #selector(cleanUp), name: .UIApplicationWillTerminate, object: nil)
        
        try? syncronize() // syncronize at launch
        
        resumeLongLivedOperationsIfPossible()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Public

extension Cloud {
    
    /// Start syncronization
    public func syncronize() throws {
        guard !syncing else { throw CloudError.AlreadySyncing }
        
        print("Cloud >> Start syncronization.")
        syncing = true
        
        Promise(value: ()).then(on: dispatchQueue) { [weak self] Void -> Promise<CKAccountStatus> in
            
            guard let s = self else { throw NSError.cancelledError() }
            return s.container.accountStatus()
            
        }.then { [weak self] accountStatus -> Promise<Void> in
            
            guard let s = self else { throw NSError.cancelledError() }
            guard case .available = accountStatus else { throw CloudError.ICloudAccountNotAvailable }
            return s.setupCustomZoneIfNeeded()
            
        }.then { [weak self] Void -> Promise<Void> in
            
            guard let s = self else { throw NSError.cancelledError() }
            if s.cancelled { throw NSError.cancelledError() }
            return s.getChangesFromCloud()
            
        }.always { [weak self] in
                
            print("Cloud >> Syncronization finished.")
            self?.finish()
                
        }.catch { error in
            
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
    
    func setupPushNotificationIfNeeded() {
        NotificationCenter.default.addObserver(
            forName: .databaseDidChangeRemotely,
            object: nil,
            queue: OperationQueue.main,
            using: { [weak self] _ in
                guard let s = self else { return }
                try? s.syncronize()
            })
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
    private func getChangesFromCloud() -> Promise<Void> {
        return Promise<Void> { [unowned self] fullfill, reject in
            Promise(value: ()).then(on: dispatchQueue) {
                () -> Promise<(toSave: [CKRecord], toDelete: [CKRecordID], lastChangeToken: CKServerChangeToken?)> in
                
                print("Cloud >> Fetch changes from private database.")
                
                return self.fetchChanges(from: self.databases.private)
                
            }.then { (modification, deletion, token) -> Void in
                
                print("Cloud >> Send data to changeManager to save to disk.")
                
                self.changeManager.handleSyncronizationGet(modification: modification, deletion: deletion)
                Defaults.changeToken = token
                
                print("Cloud >> Change saved")
                
            }.catch { error in
                
                reject(error)
                
            }
        }
    }
    
    private func pushChangesOntoCloud() -> Promise<Void> {
        return Promise<Void> { [weak self] fullfill, reject in
            
            Promise(value: ()).then(on: dispatchQueue) {
                () -> ([CKRecord], [CKRecordID]) in
                
                guard let s = self else { throw NSError.cancelledError() }
                
                let uploads = try s.changeManager.generateUploads()
                return (uploads.modification, uploads.deletion)
                
            }.then { (modification, deletion) -> Promise<(saved: [CKRecord]?, deleted: [CKRecordID]?)> in
                
                print("Cloud >> Push local changes to cloud.")
                guard let s = self else { throw NSError.cancelledError() }
                
                return s.pushChanges(to: s.databases.private, saving: modification, deleting: deletion)
                
            }.then { saved, deleted -> Void in
                
                print("Cloud >> Upload finished.")
                guard let s = self else { throw NSError.cancelledError() }
                    
                try s.changeManager.finishUploads(saved: saved, deleted: deleted)
                fullfill(())
                    
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
        
            let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: [zoneID], optionsByRecordZoneID: [zoneID: option])
            operation.isLongLived = true
            
            operation.recordChangedBlock = { record in
                recordsToSave.append(record)
            }
            
            operation.recordWithIDWasDeletedBlock = { id, token in
                recordsToDelete.append(id)
            }
            
            operation.recordZoneChangeTokensUpdatedBlock = { (zoneId, token, data) in
                lastChangeToken = token
            }
            
            operation.recordZoneFetchCompletionBlock = { (zoneId, changeToken, _, _, error) in
                if let error = error {
                    reject(error)
                    print("Cloud >>>> Error fetching zone changes for \(String(describing: Defaults.changeToken)) database.")
                    return
                }
                lastChangeToken = changeToken
            }
            
            operation.fetchRecordZoneChangesCompletionBlock = { error in
                if let error = error {
                    reject(error)
                    print("Cloud >>>> Error fetching zone changes for \(String(describing: Defaults.changeToken)) database.")
                    return
                }
                
                fullfill((recordsToSave, recordsToDelete, lastChangeToken))
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
            operation.modifyRecordsCompletionBlock = { saved, deleted, error in
                if let error = (error as? CKError),
                    case .partialFailure = error.code {
                        print("Cloud >>>> Only apart of uploads are successfully applied to cloud.")
                }
                fullfill((saved, deleted))
            }
            
            operation.qualityOfService = .utility
            database.add(operation)
        }
    }
    
    private func resumeLongLivedOperationsIfPossible() {
        CKContainer.default().fetchAllLongLivedOperationIDs { ( opeIDs, error) in
            guard error == nil else { return }
            guard let ids = opeIDs else { return }
            for id in ids {
                CKContainer.default().fetchLongLivedOperation(withID: id, completionHandler: { (ope, error) in
                    guard error == nil else { return }
                    if let modifyOp = ope as? CKModifyRecordsOperation {
                        modifyOp.modifyRecordsCompletionBlock = { (_,_,_) in
                            print("Resume modify records success!")
                        }
                        CKContainer.default().add(modifyOp)
                    }
                })
            }
        }
    }
    
    private func finish() {
        syncing = false
    }
}

extension Cloud {
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
}


