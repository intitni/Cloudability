import Foundation
import RealmSwift


/// `PendingRelationship` is used to mark down the relationships noted in `CKRecord`s,
/// after all data are fetched from cloud, the newly generated or persisted `PendingRelationship`
/// will be consumed to set relationship related properties of some objects.
///
/// If a `PendingRelationship` can not be applied (when an end of the relationship is not yet there)
/// the object will be persisted in database, waiting for the next sync.
class PendingRelationship: Object {
    @objc dynamic var id: String!
    @objc dynamic var fromType: String! { didSet { setID() } }
    @objc dynamic var fromIdentifier: String! { didSet { setID() } }
    @objc dynamic var propertyName: String! { didSet { setID() } }
    @objc dynamic var toType: String!
    var targetIdentifiers = List<String>()
    
    @objc dynamic var isApplied = false
    
    override class func primaryKey() -> String? { return "id" }
    
    private func setID() {
        guard let t = fromType, let i = fromIdentifier, let p = propertyName else { return }
        id = [t,i,p].joined(separator: "-")
    }
}

enum PendingRelationshipError: Error {
    case partiallyConnected
    case dataCorrupted
}

extension Realm {
    
    var pendingRelationships: Results<PendingRelationship> {
        return objects(PendingRelationship.self)
    }
    
    /// - Warning
    /// Must be inside write transaction
    func apply(_ pendingRelationship: PendingRelationship) throws {
        let fromType = realmObjectType(forName: pendingRelationship.fromType)!
        guard let fromTypeObject = object(ofType: fromType, forPrimaryKey: pendingRelationship.fromIdentifier)
            else { throw PendingRelationshipError.partiallyConnected }
        
        guard let object = fromTypeObject as? CloudableObject else {
            dPrint("Object for type '\(pendingRelationship.fromType)' in PendingRelationship is not Cloudable.")
            throw PendingRelationshipError.dataCorrupted
        }
        
        guard let property = object.objectSchema.properties
            .filter({ $0.name == pendingRelationship.propertyName })
            .first
        else {
            dPrint("Object for type '\(object.recordType)' doesn't have property named '\(pendingRelationship.propertyName)'")
            throw PendingRelationshipError.dataCorrupted
        }
        
        guard property.type == .object else {
            dPrint("Property '\(object.recordType).\(pendingRelationship.propertyName)' is not pointing to object(s).")
            throw PendingRelationshipError.dataCorrupted
        }
        
        let ids = pendingRelationship.targetIdentifiers
        
        //let toType = realmObjectType(forName: pendingRelationship.toType)
        let objectFetcher: (String) -> DynamicObject? = { [unowned self] id in
            return self.dynamicObject(ofType: pendingRelationship.toType, forPrimaryKey: id)
        }
        if property.isArray {
            var everyoneok = true
            let targets = object.dynamicList(property.name)
            targets.removeAll()
            for id in ids {
                guard let target = objectFetcher(id) else { everyoneok = false; continue }
                targets.append(target)
            }
            if !everyoneok { throw PendingRelationshipError.partiallyConnected }
        } else {
            guard let id = ids.first else { object[property.name] = nil; return }
            guard let target = objectFetcher(id) else { throw PendingRelationshipError.partiallyConnected }
            object[property.name] = target
        }
    }
}
