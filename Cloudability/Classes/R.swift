import Foundation
import RealmSwift

typealias ID = String

/// tool methods for Cloudablity.
public extension Realm {
    /// Realm to store `SyncedEntity` and `PendingRelationship`.
    static var cloudRealm: Realm {
        let documentDirectory = try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                             appropriateFor: nil, create: false)
        let url = documentDirectory.appendingPathComponent("cloudability.realm")
        let conf = Realm.Configuration(fileURL: url, objectTypes: [SyncedEntity.self, PendingRelationship.self])
        return try! Realm(configuration: conf)
    }
    
    /// Deletes an CloudableObject from the Realm. You should always use this method to delete a CloudableObject so Cloudability can handle the deletion.
    ///
    /// If you don't want Cloudability to pollute your codes, you are welcome to soft delete your objects so Cloudability can listen to them as modifications.
    ///
    /// - Warning
    /// This method may only be called during a write transaction.
    public func delete(cloudableObject: CloudableObject) {
        let id = cloudableObject.pkProperty
        delete(cloudableObject)
        
        let cRealm = Realm.cloudRealm
        try? cRealm.safeWrite {
            guard let syncedEntity = cRealm.object(ofType: SyncedEntity.self, forPrimaryKey: id)
                else { return }
            syncedEntity.changeState = .deleted
        }
    }
    
    /// Write that starts transaction only when it's not in transaction.
    public func safeWrite(withoutNotifying tokens: [NotificationToken] = [], _ block: (() throws -> Void)) throws {
        if isInWriteTransaction {
            try block()
        } else {
            beginWrite()
            do { try block() }
            catch {
                if isInWriteTransaction { cancelWrite() }
                throw error
            }
            if isInWriteTransaction { try commitWrite(withoutNotifying: tokens) } // if not closed by others
        }
    }
    
    public func enumerateCloudableTypes(_ block: (CloudableObject.Type) -> Void) {
        for schema in schema.objectSchema {
            let objClass = realmObjectType(forName: schema.className)!
            guard let objectClass = objClass as? CloudableObject.Type else { continue }
            block(objectClass)
        }
    }
    
    public func enumerateCloudableLists(_ block: (Results<Object>, CloudableObject.Type) -> Void) {
        enumerateCloudableTypes { objectClass in
            let objs = objects(objectClass)
            block(objs, objectClass)
        }
    }
    
    public func enumerateCloudableObjects(_ block: (CloudableObject, CloudableObject.Type) -> Void) {
        enumerateCloudableLists { objs, objectClass in
            for obj in objs {
                block(obj as! CloudableObject, objectClass)
            }
        }
    }
}


internal func log(_ item: @autoclosure () -> Any) {
    print(item())
}

internal func logError(_ item: @autoclosure () -> Any, file: String = #file, function: String = #function, line: Int = #line) {
    print("\(file).\(function) @line")
    print(item())
}

