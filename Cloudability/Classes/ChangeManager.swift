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
    weak var cloud: Cloud!
    
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
    
    init() {
        setupObservations()
    }
    
    deinit {
        collectionInsertionObservations.forEach { $0.invalidate() }
        objectObservations.forEach { $0.1.invalidate() }
    }
}

extension ChangeManager {
    func setupSyncedEntities() {
        guard r.syncedEntities.count <= 0 else {
            print("ChangeManager >> Synced entities already setup.")
            return
        }
        
        print("ChangeManager >> Setting up synced entities.")
        
        for schema in r.realm.schema.objectSchema {
            let objectClass = realmObjectType(forName: schema.className)
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
        
        print("ChangeManager >> All synced entities set up.")
    }
    
    func detachSyncedEntities() throws {
        try r.write { realm in
            _ = r.syncedEntities.map(realm.delete)
        }
    }
    
    func handleSyncronizationGet(modification: [CKRecord], deletion: [CKRecordID]) throws {
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
    private func setupObservations() {
        for schema in r.realm.schema.objectSchema {
            let objectClass = realmObjectType(forName: schema.className)
            guard objectClass is CloudableObject.Type else { continue }
            let primaryKey = objectClass.primaryKey()!
            let results = r.realm.objects(objectClass)
            
            let token = results.observe { change in
                switch change {
                case .initial: break
                case let .update(_, _, insertions, _):
                    break // do something
                case .error(let e): print(e.localizedDescription)
                }
            }
            collectionInsertionObservations.append(token)
            
            for object in results {
                let token = object.observe { change in
                    switch change {
                    case .change(let properties):
                        break // do something
                    case .deleted:
                        break // do something
                    case .error(let e): print(e.localizedDescription)
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
        try? r.write { realm in
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
                
                try r.write { realm in
                    realm.add(object, update: true)
                    realm.add(pendingRelationships, update: true)
                    syncedEntity.changeState = .synced
                    realm.add(syncedEntity, update: true)
                }
                
            } catch {
                print(error.localizedDescription)
            }
        }
    }
}

