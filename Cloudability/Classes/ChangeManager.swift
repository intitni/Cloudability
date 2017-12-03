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

let changeManager = ChangeManager()

class ChangeManager {
    var collectionInsertionObservations = [NotificationToken]()
    var objectObservations = [ID: NotificationToken]()
    
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
    
    fileprivate init() {
        setupObservations()
    }
    
    deinit {
        collectionInsertionObservations.forEach { $0.stop() }
        objectObservations.forEach { $0.1.stop() }
    }
}

extension ChangeManager {
    func setupSyncedEntities() {
        guard store.syncedEntities.count <= 0 else {
            dPrint("ChangeManager >> Synced entities already setup.")
            return
        }
        
        dPrint("ChangeManager >> Setting up synced entities.")
        
        for schema in store.realm.schema.objectSchema {
            let objectClass = realmObjectType(forName: schema.className)
            guard objectClass is CloudableObject.Type else { continue }
            let primaryKey = objectClass.primaryKey()!
            let results = store.realm.objects(objectClass)
            
            let syncedEntities = results.map {
                SyncedEntity(type: schema.className, identifier: $0[primaryKey] as! String, state: 0)
            }
            
            try! store.write { realm in
                realm.add(syncedEntities)
            }
        }
        
        dPrint("ChangeManager >> All synced entities set up.")
    }
    
    func detachSyncedEntities() throws {
        try store.write { realm in
            _ = store.syncedEntities.map(realm.delete)
        }
    }
    
    func handleSyncronizationGet(modification: [CKRecord], deletion: [CKRecordID]) throws {
        let m: [Modification] = modification.map {
                return Modification(syncedEntity: store.syncedEntity(withIdentifier: $0.recordID.recordName),
                                    record: $0)
            }
    
        let d: [Deletion] = deletion
            .flatMap { recordID in
                let identifier = recordID.recordName
                guard let se = store.syncedEntity(withIdentifier: identifier) else { return nil }
                return Deletion(syncedEntity: SyncedEntity(value: se))
            }
        
        writeToDisk(modification: m, deletion: d)
    }
    
    func generateUploads() throws -> (modification: [CKRecord], deletion: [CKRecordID]) {
        let uploadingModificationSyncedEntities = Array(store.syncedEntities(of: [.inserted, .changed]))
        let uploadingDeletionSyncedEntities = Array(store.syncedEntities(of: .deleted))
        
        let objectConverter = ObjectConverter()
        
        let modification: [CKRecord] = uploadingModificationSyncedEntities.flatMap {
            let object = realm.object(ofType: $0.objectType, forPrimaryKey: $0.identifier)
            return (object as? Object & CanUploadToCloud).map(objectConverter.convert)
        }
        
        let deletion: [CKRecordID] = uploadingDeletionSyncedEntities.map {
            return CKRecordID(recordName: $0.identifier, zoneID: zoneID)
        }
        
        return (modification, deletion)
    }
    
    func finishUploads(saved: [CKRecord]?, deleted: [CKRecordID]?) throws {
        let savedEntities: [SyncedEntity] = saved?
            .flatMap { record in
                let id = record.recordID.recordName
                return store.syncedEntity(withIdentifier: id)
            } ?? []
        let deletedEntites: [SyncedEntity] = deleted?
            .flatMap { recordID in
                return store.syncedEntity(withIdentifier: recordID.recordName)
            } ?? []
        
        try store.write { realm in
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
    private func setupObservations() {
        for schema in store.realm.schema.objectSchema {
            let objectClass = realmObjectType(forName: schema.className)
            guard objectClass is CloudableObject.Type else { continue }
            let primaryKey = objectClass.primaryKey()!
            let results = store.realm.objects(objectClass)
            
            let token = results.addNotificationBlock { change in
                switch change {
                case .initial: break
                case let .update(_, _, insertions, _):
                    // do something
                case .error(let e): dPrint(e.localizedDescription)
                }
            }
            collectionInsertionObservations.append(token)
            
            for object in results {
                let token = object.addNotificationBlock { change in
                    switch change {
                    case .change(let properties):
                        // do something
                    case .deleted:
                        // do something
                    case .error(let e): dPrint(e.localizedDescription)
                    }
                }
                
                objectObservations[object[primaryKey] as! String] = token
            }
        }
    }
    
    private func writeToDisk(modification: [Modification], deletion: [Deletion]) {
        writeToDisk(deletion: deletion)
        writeToDisk(modification: modification)
    }
}

extension ChangeManager {
    private func writeToDisk(deletion: [Deletion]) {
        try? store.write { realm in
            for d in deletion {
                let syncedEntity = d.syncedEntity
                let identifier = syncedEntity.identifier
                let type = realmObjectType(forName: syncedEntity.type)
                let object = realm.object(ofType: type, forPrimaryKey: identifier)
                realm.delete(syncedEntity)
                if let object = object { realm.delete(object) }
            }
        }
    }
    
    private func writeToDisk(modification: [Modification]) {
        for m in modification {
            let ckRecord = m.record
            let (object, pendingRelationships) = ObjectConverter().convert(ckRecord)
            do {
                let syncedEntity = m.syncedEntity
                                 ?? SyncedEntity(type: ckRecord.recordType, identifier: ckRecord.recordID.recordName, state: 0)
                
                try realm.write {
                    realm.add(object, update: true)
                    realm.add(pendingRelationships, update: true)
                    syncedEntity.changeState = .synced
                    realm.add(syncedEntity, update: true)
                }
                
                // following behaviours
                switch syncedEntity.type {
                case Item.className():
                    let item = object as! Item
                    try store.setupNotifications(for: item)
                case ItemKind.className(): break
                case Category.className(): break
                case ForwardStrategy.className(): break
                case InStockStrategy.className(): break
                default: fatalError()
                }
            } catch {
                dPrint(error.localizedDescription)
            }
        }
    }
}

