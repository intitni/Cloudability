//
//  SyncedEntity.swift
//  BestBefore
//
//  Created by Shangxin Guo on 30/10/2017.
//  Copyright © 2017 Inti Guo. All rights reserved.
//

import RealmSwift

/// SyncedEntity is a reference interface of Object stored locally to ChangeManager,
/// to determine which object it is that the CKRecord or CKRecordID points to.
class SyncedEntity: Object {
    enum ChangeState: Int {
        case new = 0, changed, deleted, inserted, synced
    }
    
    @objc dynamic var identifier: String = ""
    @objc dynamic var type: String = ""
    @objc dynamic var state: Int = 0
    @objc dynamic var changedKeys: String?
    @objc dynamic var modifiedTime: Date?
    
    convenience init(type: String, identifier: String, state: Int) {
        self.init()
        
        self.type = type
        self.identifier = identifier
        self.state = state
    }
    
    override class func primaryKey() -> String? {
        return "identifier"
    }
    
    override class func indexedProperties() -> [String] { return ["identifier", "type"] }
    
    override class func ignoredProperties() -> [String] { return ["objectType"] }
    
    var changeState: ChangeState {
        get { return ChangeState(rawValue: state) ?? .new }
        set { state = newValue.rawValue }
    }
    
    var objectType: Object.Type {
        get {
            return realmObjectType(forName: type)
        }
        set {
            type = newValue.className()
        }
    }
    
    private func realmObjectType(forName name: String) -> Object.Type {
        if let objClass = NSClassFromString(name) {
            return objClass as! Object.Type
        } else {
            let namespace = Bundle.main.infoDictionary!["CFBundleExecutable"] as! String
            return NSClassFromString("\(namespace).\(name)") as! Object.Type
        }
    }
}

extension ItemStore {
    var syncedEntities: Results<SyncedEntity> {
        return realm.objects(SyncedEntity.self)
    }
    
    func syncedEntity(withIdentifier identifier: ID) -> SyncedEntity? {
        guard identifier != "" else { return nil }
        return syncedEntities
            .filter(NSPredicate(format: "identifier == %@", identifier))
            .last
    }
    
    func syncedEntities(of state: SyncedEntity.ChangeState) -> Results<SyncedEntity> {
        return syncedEntities
            .filter(NSPredicate(format: "state == \(state.rawValue)"))
    }
    
    func syncedEntities(of states: [SyncedEntity.ChangeState]) -> Results<SyncedEntity> {
        let predicateFormat = states.map { "state == \($0.rawValue)" }.joined(separator: " || ")
        return syncedEntities
            .filter(NSPredicate(format: predicateFormat))
    }
    
    var unsyncedSyncedEntities: Results<SyncedEntity> {
        return syncedEntities
            .filter(NSPredicate(format: "state != \(SyncedEntity.ChangeState.synced.rawValue)"))
    }
}



