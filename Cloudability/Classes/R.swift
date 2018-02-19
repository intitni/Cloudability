import Foundation
import RealmSwift

typealias ID = String

/// tool methods for Cloudablity.
public extension Realm {
    static var cloudRealm: Realm {
        let documentDirectory = try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                             appropriateFor: nil, create: false)
        let url = documentDirectory.appendingPathComponent("cloudability.realm")
        let conf = Realm.Configuration(fileURL: url, objectTypes: [SyncedEntity.self, PendingRelationship.self])
        return try! Realm(configuration: conf)
    }
    
    ///Deletes an CloudableObject from the Realm.
    /// - Warning
    /// This method may only be called during a write transaction.
    public func delete(cloudableObject: CloudableObject) {
        let id = cloudableObject.pkProperty
        delete(cloudableObject)
        guard let syncedEntity = object(ofType: SyncedEntity.self, forPrimaryKey: id)
            else { return }
        syncedEntity.changeState = .deleted
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
            if isInWriteTransaction { try commitWrite(withoutNotifying: tokens) }
        }
    }
}


internal func dPrint(_ item: @autoclosure () -> Any) {
    #if DEBUG
        print(item())
    #endif
}

