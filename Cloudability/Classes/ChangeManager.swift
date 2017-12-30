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
    
    weak var cloud: Cloud?
    
    var collectionInsertionObservations = [NotificationToken]()
    
    init() {
        setupLocalDatabaseObservations()
    }
    
    deinit {
        collectionInsertionObservations.forEach { $0.invalidate() }
    }
}

extension ChangeManager {
    var allZoneIDs: [CKRecordZoneID] {
        let realm = try! Realm()
        return realm.schema.objectSchema.flatMap {
            let objClass = realmObjectType(forName: $0.className)!
            guard let objectClass = objClass as? CloudableObject.Type else { return nil }
            return objectClass.zoneID
        }
    }
    
    func handleSyncronizationGet(modification: [CKRecord], deletion: [CKRecordID]) {
        let realm = try! Realm()
        let m: [Modification] = modification.map {
                return Modification(syncedEntity: realm.syncedEntity(withIdentifier: $0.recordID.recordName),
                                    record: $0)
            }
    
        let d: [Deletion] = deletion
            .flatMap { recordID in
                let identifier = recordID.recordName
                guard let se = realm.syncedEntity(withIdentifier: identifier) else { return nil }
                return Deletion(syncedEntity: SyncedEntity(value: se))
            }
        
        writeToDisk(modification: m, deletion: d)
    }
    
    func finishUploads(saved: [CKRecord]?, deleted: [CKRecordID]?) {
        let realm = try! Realm()
        let savedEntities: [SyncedEntity] = saved?
            .flatMap { record in
                let id = record.recordID.recordName
                return realm.syncedEntity(withIdentifier: id)
            } ?? []
        let deletedEntites: [SyncedEntity] = deleted?
            .flatMap { recordID in
                return realm.syncedEntity(withIdentifier: recordID.recordName)
            } ?? []
        
        try? realm.safeWrite(withoutNotifying: collectionInsertionObservations) {
            for entity in savedEntities {
                entity.changeState = .synced
                entity.modifiedTime = Date()
                realm.add(entity, update: true)
            }
            
            for entity in deletedEntites {
                entity.modifiedTime = Date()
                entity.isDeleted = true
                realm.add(entity, update: true)
            }
        }
    }
    
    func cleanUp() {
        let realm = try! Realm()
        try? realm.safeWrite(withoutNotifying: collectionInsertionObservations) {
            let deletedSyncedEntities = realm.objects(SyncedEntity.self).filter("isDeleted == true")
            let appliedPendingRelationships = realm.objects(SyncedEntity.self).filter("isApplied == true")
            realm.delete(deletedSyncedEntities)
            realm.delete(appliedPendingRelationships)
        }
    }
}

extension ChangeManager {
    func setupSyncedEntitiesIfNeeded() {
        let realm = try! Realm()
        guard realm.objects(SyncedEntity.self).count <= 0 else {
            dPrint("ChangeManager >> Synced entities already setup.")
            return
        }
        
        dPrint("ChangeManager >> Setting up synced entities.")
        
        try? realm.safeWrite(withoutNotifying: collectionInsertionObservations) {
            for schema in realm.schema.objectSchema {
                let objectClass = realmObjectType(forName: schema.className)!
                guard objectClass is CloudableObject.Type else { continue }
                let primaryKey = objectClass.primaryKey()!
                let results = realm.objects(objectClass)
                
                let syncedEntities = results.map {
                    SyncedEntity(type: schema.className, identifier: $0[primaryKey] as! String, state: 0)
                }
                
                realm.add(syncedEntities)
            }
        }
        
        dPrint("ChangeManager >> All synced entities setup.")
    }
    
    func detachSyncedEntities() {
        let realm = try! Realm()
        try? realm.safeWrite(withoutNotifying: collectionInsertionObservations) {
            _ = realm.syncedEntities.map(realm.delete)
        }
    }
    
    /// Observe all Cloudable object lists, for insertions and modifications.
    private func setupLocalDatabaseObservations() {
        let realm = try! Realm()
        for schema in realm.schema.objectSchema {
            let objClass = realmObjectType(forName: schema.className)!
            guard let objectClass = objClass as? CloudableObject.Type else { continue }
            let results = realm.objects(objectClass)
            
            let token = results.observe { [weak self] change in
                switch change {
                case .initial: break
                case .error(let e): dPrint(e.localizedDescription)
                    
                // We should not see any true deletion, soft deletion should be used in Cloudable objects.
                case let .update(result, _, insertion, modification):
                    dPrint("ChangeManager >> Change detected.")
                    guard let ego = self else { return }
                    
                    /// All insertions and modifications, not marked as soft deleted
                    let m: [CloudableObject] = (insertion + modification)
                        .filter { $0 < result.count }
                        .map { result[$0] as! CloudableObject }
                    
                    ego.handleLocalModification(modification: m)
                    let uploads = ego.generateUploads(forSpecificType: objectClass)
                    try? ego.cloud?.push(modification: uploads.modification, deletion: uploads.deletion)
                }
            }
            collectionInsertionObservations.append(token)
        }
    }
    
    func generateUploads(forSpecificType type: CloudableObject.Type? = nil) -> (modification: [CKRecord], deletion: [CKRecordID]) {
        let realm = try! Realm()
        
        func syncedEntity(of changeState: [SyncedEntity.ChangeState]) -> [SyncedEntity] {
            if let type = type {
                return Array(realm.syncedEntities(of: changeState).filter("type == \"\(type.className())\""))
            }
            return Array(realm.syncedEntities(of: changeState))
        }
        
        let uploadingModificationSyncedEntities = syncedEntity(of: [.new, .changed])
        let uploadingDeletionSyncedEntities = syncedEntity(of: [.deleted])
        
        let objectConverter = ObjectConverter()
        
        let modification: [CKRecord] = uploadingModificationSyncedEntities.flatMap {
            let object = realm.object(ofType: $0.objectType, forPrimaryKey: $0.identifier)
            return (object as? CloudableObject).map(objectConverter.convert)
        }
        
        let deletion: [CKRecordID] = uploadingDeletionSyncedEntities.map {
            return CKRecordID(recordName: $0.identifier, zoneID: $0.objectType.zoneID) 
        }
        
        return (modification, deletion)
    }
    
    /// Write modifications and deletions to disk.
    private func writeToDisk(modification: [Modification], deletion: [Deletion]) {
        dPrint("ChangeManager >> Writing deletions.")
        writeToDisk(deletion: deletion)
        
        dPrint("ChangeManager >> Writing modifications.")
        writeToDisk(modification: modification)
        
        dPrint("ChangeManager >> Writing relationships.")
        applyPendingRelationships()
    }
    
    private func applyPendingRelationships() {
        let realm = try! Realm()
        try? realm.safeWrite(withoutNotifying: collectionInsertionObservations) {
            for relationship in realm.pendingRelationships {
                do {
                    try realm.apply(relationship)
                    realm.delete(relationship)
                } catch PendingRelationshipError.partiallyConnected {
                    dPrint("Can not fullfill PendingRelationship \(relationship.fromType).\(relationship.propertyName)")
                } catch PendingRelationshipError.dataCorrupted {
                    dPrint("Data corrupted for PendingRelationship \(relationship.fromType).\(relationship.propertyName)")
                    realm.delete(relationship)
                } catch {
                    dPrint(error.localizedDescription)
                }
            }
        }
    }
    
    /// Update `SyncedEntities`.
    private func handleLocalModification(modification: [CloudableObject]) {
        let realm = try! Realm()
        let mSyncedEntities = modification.map {
            realm.syncedEntity(withIdentifier: $0.pkProperty) ?? SyncedEntity(type: $0.recordType, identifier: $0.pkProperty, state: SyncedEntity.ChangeState.new.rawValue)
        }
        
        try? realm.safeWrite(withoutNotifying: collectionInsertionObservations) {
            for m in mSyncedEntities {
                m.changeState = .changed
                realm.add(m, update: true)
            }
        }
    }
}

extension ChangeManager {
    private func writeToDisk(deletion: [Deletion]) {
        let realm = try! Realm()
        try? realm.safeWrite(withoutNotifying: collectionInsertionObservations) {
            for d in deletion {
                let syncedEntity = d.syncedEntity
                let identifier = syncedEntity.identifier
                let type = realmObjectType(forName: syncedEntity.type)!
                let object = realm.object(ofType: type, forPrimaryKey: identifier)
                syncedEntity.isDeleted = true
                syncedEntity.changeState = .synced
                realm.add(syncedEntity, update: true)
                if let object = object as? CloudableObject {
                    realm.delete(object)
                }
            }
        }
    }
    
    private func writeToDisk(modification: [Modification]) {
        let realm = try! Realm()
        try? realm.safeWrite(withoutNotifying: collectionInsertionObservations) {
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
        }
    }
}

