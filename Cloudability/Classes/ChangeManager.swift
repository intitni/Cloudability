//
//  ChangeManager.swift
//  BestBefore
//
//  Created by Shangxin Guo on 30/10/2017.
//  Copyright © 2017 Inti Guo. All rights reserved.
//

import Foundation
import CloudKit
import PromiseKit
import RealmSwift

class ChangeManager {
    enum ChangeError: Error {
        case RecordDataNotComplete
    }
    
    private struct Deletion {
        let syncedEntity: SyncedEntity
    }
    
    private struct Modification {
        let syncedEntity: SyncedEntity?
        let record: CKRecord
    }
    
    weak var cloud: Cloud!
    
    var collectionInsertionObservations = [NotificationToken]()
    
    init() {
        setupLocalDatabaseObservations()
    }
    
    deinit {
        collectionInsertionObservations.forEach { $0.invalidate() }
    }
}

extension ChangeManager {
    func handleSyncronizationGet(modification: [CKRecord], deletion: [CKRecordID]) {
        let m: [Modification] = modification.map {
                return Modification(syncedEntity: r.syncedEntity(withIdentifier: $0.recordID.recordName),
                                    record: $0)
            }
    
        let d: [Deletion] = deletion
            .flatMap { recordID in
                let identifier = recordID.recordName
                guard let se = r.syncedEntity(withIdentifier: identifier) else { return nil }
                return Deletion(syncedEntity: SyncedEntity(value: se))
            }
        
        writeToDisk(modification: m, deletion: d)
    }
    
    func generateUploads() throws -> (modification: [CKRecord], deletion: [CKRecordID]) {
        let uploadingModificationSyncedEntities = Array(r.syncedEntities(of: [.inserted, .changed]))
        let uploadingDeletionSyncedEntities = Array(r.syncedEntities(of: .deleted))
        
        let objectConverter = ObjectConverter()
        
        let modification: [CKRecord] = uploadingModificationSyncedEntities.flatMap {
            let object = r.realm.object(ofType: $0.objectType, forPrimaryKey: $0.identifier)
            return (object as? CloudableObject).map(objectConverter.convert)
        }
        
        let deletion: [CKRecordID] = uploadingDeletionSyncedEntities.map {
            return CKRecordID(recordName: $0.identifier, zoneID: cloud.zoneID)
        }
        
        return (modification, deletion)
    }
    
    func finishUploads(saved: [CKRecord]?, deleted: [CKRecordID]?) throws {
        let savedEntities: [SyncedEntity] = saved?
            .flatMap { record in
                let id = record.recordID.recordName
                return r.syncedEntity(withIdentifier: id)
            } ?? []
        let deletedEntites: [SyncedEntity] = deleted?
            .flatMap { recordID in
                return r.syncedEntity(withIdentifier: recordID.recordName)
            } ?? []
        
        try r.write { realm in
            for entity in savedEntities {
                entity.changeState = .synced
                realm.add(entity, update: true)
            }
            
            for entity in deletedEntites {
                realm.delete(entity)
            }
        }
    }
}

extension ChangeManager {
    func setupSyncedEntitiesIfNeeded() {
        guard r.syncedEntities.count <= 0 else {
            print("ChangeManager >> Synced entities already setup.")
            return
        }
        
        print("ChangeManager >> Setting up synced entities.")
        
        for schema in r.realm.schema.objectSchema {
            let objectClass = realmObjectType(forName: schema.className)!
            guard objectClass is CloudableObject.Type else { continue }
            let primaryKey = objectClass.primaryKey()!
            let results = r.realm.objects(objectClass)
            
            let syncedEntities = results.map {
                SyncedEntity(type: schema.className, identifier: $0[primaryKey] as! String, state: 0)
            }
            
            try! r.write { realm in
                realm.add(syncedEntities)
            }
        }
        print("ChangeManager >> All synced entities setup.")
    }
    
    func detachSyncedEntities() {
        try? r.write { realm in
            _ = r.syncedEntities.map(realm.delete)
        }
    }
    
    /// Observe all Cloudable object lists, for insertions and modifications.
    private func setupLocalDatabaseObservations() {
        for schema in r.realm.schema.objectSchema {
            let objectClass = realmObjectType(forName: schema.className)!
            guard objectClass is CloudableObject.Type else { continue }
            let results = r.realm.objects(objectClass)
            
            let token = results.observe { [weak self] change in
                switch change {
                case .initial: break
                case .error(let e): print(e.localizedDescription)
                    
                // We should not see any true deletion, soft deletion should be used in Cloudable objects.
                case let .update(result, _, insertion, modification):
                    print("ChangeManager >> Change detected.")
                    guard let s = self else { return }                    
                    
                    /// All insertions and modifications, not marked as soft deleted
                    let m: [CloudableObject] = (insertion + modification)
                        .filter { $0 < result.count }
                        .map { result[$0] as! CloudableObject }
                        .filter { !$0.isDeleted }
                    
                    /// All soft deleted objects that changed.
                    /// (it may be objects that already been deleted but still being modified)
                    let d: [CloudableObject] = modification
                        .filter { $0 < result.count }
                        .map { result[$0] as! CloudableObject }
                        .filter { $0.isDeleted }
                
                    s.handleLocalChange(modification: m, deletion: d)
                }
            }
            collectionInsertionObservations.append(token)
        }
    }
    
    /// Write modifications and deletions to disk.
    private func writeToDisk(modification: [Modification], deletion: [Deletion]) {
        writeToDisk(deletion: deletion)
        writeToDisk(modification: modification)
    }
    
    /// Update `SyncedEntities` then call `cloud` to `syncronize()`.
    private func handleLocalChange(modification: [CloudableObject], deletion: [CloudableObject]) {
        let mSyncedEntities = modification.map {
            r.syncedEntity(withIdentifier: $0.pkProperty) ?? SyncedEntity(type: $0.recordType, identifier: $0.pkProperty, state: SyncedEntity.ChangeState.new.rawValue)
        }
        
        let dSyncedEntities = deletion.map {
            r.syncedEntity(withIdentifier: $0.pkProperty) ?? SyncedEntity(type: $0.recordType, identifier: $0.pkProperty, state: SyncedEntity.ChangeState.new.rawValue)
        }
        
        do {
            let realm = try Realm()
            realm.beginWrite()
            try r.write { realm in
                for m in mSyncedEntities {
                    m.changeState = .changed
                    realm.add(m, update: true)
                }
                
                for d in dSyncedEntities {
                    d.changeState = .changed
                    realm.add(d, update: true)
                }
            }
            
            try realm.commitWrite(withoutNotifying: collectionInsertionObservations)
            
            try cloud?.syncronize()
        } catch {
            print(error.localizedDescription)
        }
    }
}

extension ChangeManager {
    private func writeToDisk(deletion: [Deletion]) {
        do {
            let realm = try Realm()
            realm.beginWrite()
            
            for d in deletion {
                let syncedEntity = d.syncedEntity
                let identifier = syncedEntity.identifier
                let type = realmObjectType(forName: syncedEntity.type)!
                let object = realm.object(ofType: type, forPrimaryKey: identifier)
                syncedEntity.isDeleted = true
                syncedEntity.changeState = .synced
                realm.add(syncedEntity, update: true)
                if let object = object as? CloudableObject {
                    object.isDeleted = true
                    realm.add(object, update: true)
                }
            }
            
            try realm.commitWrite(withoutNotifying: collectionInsertionObservations)
        } catch {
            print(error.localizedDescription)
        }
    }
    
    private func writeToDisk(modification: [Modification]) {
        do {
            let realm = try Realm()
            realm.beginWrite()
            
            for m in modification {
                let ckRecord = m.record
                let (object, pendingRelationships) = ObjectConverter().convert(ckRecord)
                let syncedEntity = m.syncedEntity
                                ?? SyncedEntity(type: ckRecord.recordType, identifier: ckRecord.recordID.recordName, state: 0)
                
                realm.add(object, update: true)
                realm.add(pendingRelationships, update: true)
                syncedEntity.changeState = .synced
                realm.add(syncedEntity, update: true)
            }
            
            try realm.commitWrite(withoutNotifying: collectionInsertionObservations)
        } catch {
            print(error.localizedDescription)
        }
    }
}

