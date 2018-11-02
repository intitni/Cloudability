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

protocol ChangeManagerObserver: class {
    func changeManagerDidObserveChanges(modification: [CKRecord], deletion: [CKRecord.ID])
}

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
    
    weak var observer: ChangeManagerObserver?
    
    var collectionObservations = [NotificationToken]()
    let zoneType: ZoneType
    
    var objectConverter: ObjectConverter {
        return .init(zoneType: zoneType)
    }
    
    init(zoneType: ZoneType = .individualForEachRecordType) {
        self.zoneType = zoneType
        validateCloudableObjects()
        setupLocalDatabaseObservations()
    }
    
    deinit {
        collectionObservations.forEach { $0.invalidate() }
    }
    
    var allZoneIDs: [CKRecordZone.ID] {
        let realm = try! Realm()
        switch zoneType {
        case .individualForEachRecordType:
            var result = [CKRecordZone.ID]()
            realm.enumerateCloudableTypes { type in
                result.append(objectConverter.zoneID(for: type))
            }
            return result
        case .customRule(let rule):
            var result = [CKRecordZone.ID]()
            realm.enumerateCloudableTypes { type in
                result.append(rule(type))
            }
            return result
        case .defaultZone:
            return [CKRecordZone.default().zoneID]
        case .sameZone(let name):
            return [CKRecordZone.ID(zoneName: name, ownerName: CKCurrentUserDefaultName)]
        }
    }
}

// MARK: - Setting Up / Down

extension ChangeManager {
    /// Remove useless `SyncedEntity`s and `PendingRelationship`s.
    func cleanUp() {
        let realm = Realm.cloudRealm
        try? realm.safeWrite {
            let deletedSyncedEntities = realm.objects(SyncedEntity.self).filter("isDeleted == true")
            realm.delete(deletedSyncedEntities)
            realm.delete(realm.pendingRelationshipsToBePurged)
        }
    }
    
    /// Performs when cloud switches off.
    /// 1. remove all cloud helper objects.
    /// 2. set user defaults to false.
    func tearDown() {
        let oRealm = try! Realm()
        let cRealm = Realm.cloudRealm
        try? cRealm.safeWrite {
            cRealm.deleteAll()
        }
        for schema in oRealm.schema.objectSchema {
            guard let objectClass = realmObjectType(forName: schema.className) else { continue }
            guard objectClass is CloudableObject.Type else { continue }
            Defaults.setCreatedSyncedEntity(for: schema, to: false)
        }
    }
    
    func setupSyncedEntitiesIfNeeded() {
        let cRealm = Realm.cloudRealm
        let oRealm = try! Realm()
        
        cloud_log("Set up synced entities.")
        
        try? cRealm.safeWrite() {
            for schema in oRealm.schema.objectSchema {
                guard !Defaults.createdSyncedEntity(for: schema) else { continue }
                defer { Defaults.setCreatedSyncedEntity(for: schema, to: true) }
                guard let objectClass = realmObjectType(forName: schema.className) else { continue }
                guard objectClass is CloudableObject.Type else { continue }
                let primaryKey = objectClass.primaryKey()!
                let results = oRealm.objects(objectClass)
                
                let syncedEntities = results.map {
                    SyncedEntity(type: schema.className, identifier: $0[primaryKey] as! String, state: 0)
                }
                
                cRealm.add(syncedEntities, update: true)
            }
        }
    }
}

// MARK: - Pull

extension ChangeManager {
    func handleSyncronizationGet(modification: [CKRecord], deletion: [CKRecord.ID]) {
        let realm = Realm.cloudRealm
        let m: [Modification] = modification.map {
                return Modification(syncedEntity: realm.syncedEntity(withIdentifier: $0.recordID.recordName),
                                    record: $0)
            }
    
        let d: [Deletion] = deletion
            .compactMap { recordID in
                let identifier = recordID.recordName
                guard let se = realm.syncedEntity(withIdentifier: identifier) else { return nil }
                return Deletion(syncedEntity: SyncedEntity(value: se))
            }
        
        writeToDisk(modification: m, deletion: d)
    }
}

// MARK: - Push

extension ChangeManager {
    func generateAllUploads() -> (modification: [CKRecord], deletion: [CKRecord.ID]) {
        return generateUploads(for: nil)
    }
    
    /// Update `SyncedEntity`s after upload finishes.
    func finishUploads(saved: [CKRecord]?, deleted: [CKRecord.ID]?) {
        let realm = Realm.cloudRealm
        let savedEntities: [SyncedEntity] = saved?
            .compactMap { record in
                let id = record.recordID.recordName
                return realm.syncedEntity(withIdentifier: id)
            } ?? []
        let deletedEntites: [SyncedEntity] = deleted?
            .compactMap { recordID in
                return realm.syncedEntity(withIdentifier: recordID.recordName)
            } ?? []
        
        try? realm.safeWrite {
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
    
    /// Update `SyncedEntity`s and `PendingRelationship`s.
    private func handleHelperObjectChangesDueToLocalModification(modification: [CloudableObject]) {
        let realm = Realm.cloudRealm
        let mSyncedEntities = modification.map {
            realm.syncedEntity(withIdentifier: $0.pkProperty) ?? SyncedEntity(type: $0.recordType, identifier: $0.pkProperty, state: SyncedEntity.ChangeState.new.rawValue)
        }
        
        try? realm.safeWrite {
            for m in mSyncedEntities {
                m.changeState = .changed
                realm.add(m, update: true)
                realm.sentencePendingRelationshipsToDeath(fromType: m.type, fromIdentifier: m.identifier)
            }
        }
    }
    
    private func generateUploads(for type: CloudableObject.Type?) -> (modification: [CKRecord], deletion: [CKRecord.ID]) {
        let oRealm = try! Realm()
        let cRealm = Realm.cloudRealm
        
        func syncedEntity(of changeState: [SyncedEntity.ChangeState]) -> [SyncedEntity] {
            if let type = type {
                return Array(cRealm.syncedEntities(of: changeState).filter("type == \"\(type.className())\""))
            }
            return Array(cRealm.syncedEntities(of: changeState))
        }
        
        let uploadingModificationSyncedEntities = syncedEntity(of: [.new, .changed])
        let uploadingDeletionSyncedEntities = syncedEntity(of: [.deleted])
        
        let converter = objectConverter
        
        let modification: [CKRecord] = uploadingModificationSyncedEntities.compactMap {
            let object = oRealm.object(ofType: $0.objectType, forPrimaryKey: $0.identifier)
            return (object as? CloudableObject).map(converter.convert)
        }
        
        let deletion: [CKRecord.ID] = uploadingDeletionSyncedEntities.map {
            return CKRecord.ID(recordName: $0.identifier, zoneID: converter.zoneID(for: $0.objectType))
        }
        
        return (modification, deletion)
    }
}

// MARK: - Write To Disk

extension ChangeManager {
    /// Write modifications and deletions to disk.
    private func writeToDisk(modification: [Modification], deletion: [Deletion]) {
        cloud_log("Writing deletions.")
        writeToDisk(deletion: deletion)
        
        cloud_log("Writing modifications.")
        writeToDisk(modification: modification)
        
        cloud_log("Writing relationships.")
        applyPendingRelationships()
    }
    
    private func writeToDisk(deletion: [Deletion]) {
        let oRealm = try! Realm()
        let cRealm = Realm.cloudRealm
        let objects: [Object] = deletion.compactMap {
            let syncedEntity = $0.syncedEntity
            let identifier = syncedEntity.identifier
            let type = realmObjectType(forName: syncedEntity.type)!
            return oRealm.object(ofType: type, forPrimaryKey: identifier)
        }
        
        for o in objects {
            (o as? HasBeforeDeletionAction)?.beforeCloudDeletion()
        }
        
        try? oRealm.safeWrite(withoutNotifying: collectionObservations) {
            for o in objects {
                if let object = o as? CloudableObject {
                    oRealm.delete(object)
                }
            }
        }
        
        try? cRealm.safeWrite() {
            for d in deletion {
                let syncedEntity = d.syncedEntity
                syncedEntity.isDeleted = true
                syncedEntity.changeState = .synced
                cRealm.add(syncedEntity, update: true)
            }
        }
    }
    
    private func writeToDisk(modification: [Modification]) {
        let oRealm = try! Realm()
        let cRealm = Realm.cloudRealm
        let pendingRelationshipsToBeAdded = List<PendingRelationship>()
        let syncedEntitiesToBeUpdated = List<SyncedEntity>()
        var objects = [Object]()
        try? oRealm.safeWrite(withoutNotifying: collectionObservations) {
            for m in modification {
                let ckRecord = m.record
                let (object, pendingRelationships) = objectConverter.convert(ckRecord)
                let syncedEntity = m.syncedEntity
                                ?? SyncedEntity(type: ckRecord.recordType, identifier: ckRecord.recordID.recordName, state: 0)
                oRealm.add(object, update: true)
                objects.append(object)
                pendingRelationshipsToBeAdded.append(objectsIn: pendingRelationships)
                syncedEntitiesToBeUpdated.append(syncedEntity)
            }
        }
        
        for o in objects {
            (o as? HasAfterMergeAction)?.afterCloudMerge()
        }
        
        try? cRealm.safeWrite() {
            cRealm.add(pendingRelationshipsToBeAdded, update: true)
            syncedEntitiesToBeUpdated.forEach { $0.changeState = .synced }
            cRealm.add(syncedEntitiesToBeUpdated, update: true)
        }
    }
    
    private func applyPendingRelationships() {
        let cRealm = Realm.cloudRealm
        let oRealm = try! Realm()
        let toBeDeleted = List<PendingRelationship>()
        var appliedRelationships = [PendingRelationship]()
        for relationship in cRealm.pendingRelationships {
            do {
                try oRealm.safeWrite(withoutNotifying: collectionObservations) {
                    try oRealm.apply(relationship)
                }
                try cRealm.safeWrite {
                    relationship.isApplied = true
                    relationship.attempts += 1
                }
                appliedRelationships.append(relationship)
                toBeDeleted.append(relationship)
            } catch PendingRelationshipError.partiallyConnected {
                cloud_log("Can not fullfill PendingRelationship \(String(describing: relationship.fromType)).\(String(describing: relationship.propertyName))")
                try? cRealm.safeWrite {
                    relationship.attempts += 1
                }
                appliedRelationships.append(relationship)
            } catch PendingRelationshipError.dataCorrupted {
                cloud_log("Data corrupted for PendingRelationship \(String(describing: relationship.fromType)).\(String(describing: relationship.propertyName))")
                try? cRealm.safeWrite {
                    relationship.isConsideredDead = true
                }
            } catch {
                cloud_logError(error.localizedDescription)
            }
        }
        
        var updatedObjects = [Object]()
        for relationship in appliedRelationships {
            guard let fromType = realmObjectType(forName: relationship.fromType),
                let fromTypeObject = oRealm.object(ofType: fromType, forPrimaryKey: relationship.fromIdentifier)
                else { continue }
            updatedObjects.append(fromTypeObject)
            
            let objectFetcher: (String) -> DynamicObject? = { id in
                return oRealm.dynamicObject(ofType: relationship.toType, forPrimaryKey: id)
            }
            
            for id in relationship.targetIdentifiers {
                guard let object = objectFetcher(id) else { continue }
                updatedObjects.append(object)
            }
        }
        
        for object in updatedObjects {
            (object as? HasAfterMergeAction)?.afterCloudMerge()
        }
    }
}

extension ChangeManager {
    /// Check if CloudableObjects conforms to requirements.
    func validateCloudableObjects() {
        let realm = try! Realm()
        for schema in realm.schema.objectSchema {
            guard let objClass = realmObjectType(forName: schema.className) else { continue }
            guard let _ = objClass as? CloudableObject.Type else { continue }
            assert(schema.primaryKeyProperty != nil, "\(schema.className) should provide a primary key.")
            assert(schema.primaryKeyProperty!.type == .string, "\(schema.className)'s primary key must be String.")
        }
    }
    
    /// Observe all Cloudable object lists, for insertions and modifications.
    private func setupLocalDatabaseObservations() {
        let realm = try! Realm()
        realm.enumerateCloudableLists { results, objectClass in
            let token = results.observe { [weak self] change in
                guard let ego = self else { return }
                switch change {
                case .initial: break
                case .error(let e): cloud_logError(e.localizedDescription)
                    
                // We will not see any useful information about deletion.
                // Soft deletion should be used in Cloudable objects if you want it to be here as modification.
                // Or you may use `realm.delete(cloudableObject:)` to delete objects to update `SyncedEntity` in advance.
                case let .update(result, _, insertion, modification):
                    cloud_log("Change detected.")
        
                    /// All insertions and modifications
                    let m: [CloudableObject] = (insertion + modification)
                        .filter { $0 < result.count }
                        .map { result[$0] as! CloudableObject }
                    
                    // Update `SyncedEntity`s for these modifications.
                    ego.handleHelperObjectChangesDueToLocalModification(modification: m)
                    // Generate uploads for both deletions and modifications, according to states of `SyncedEntity`s.
                    let uploads = ego.generateUploads(for: objectClass)
                    guard !(uploads.modification.isEmpty && uploads.deletion.isEmpty) else { return }
                    // Tell observer that changes happened.
                    ego.observer?.changeManagerDidObserveChanges(modification: uploads.modification, deletion: uploads.deletion)
                }
            }
            collectionObservations.append(token)
        }
    }
}

extension ChangeManager {
    fileprivate enum Defaults {
        private static let createdSyncedEntityKeyPrefix = "cloudability_created_syncedEntity_"
        static func createdSyncedEntityKey(for schema: ObjectSchema) -> String {
            return createdSyncedEntityKeyPrefix + schema.className
        }
        static func createdSyncedEntity(for schema: ObjectSchema) -> Bool {
            return UserDefaults.standard.bool(forKey: createdSyncedEntityKey(for: schema))
        }
        
        static func setCreatedSyncedEntity(for schema: ObjectSchema, to newValue: Bool) {
            UserDefaults.standard.set(newValue, forKey: createdSyncedEntityKey(for: schema))
        }
    }
}

