import Foundation
import RealmSwift
import CloudKit

public typealias CloudableObject = Object & Cloudable

public protocol Cloudable: AnyObject {
    /// Defaultly the `className()`.
    static var recordType: String { get }
    
    var recordType: String { get }
    
    var pkProperty: String { get set }
    
    var nonSyncedProperties: [String] { get }
}

public protocol HasAfterMergeAction: AnyObject {
    func afterCloudMerge()
}

public protocol HasBeforeDeletionAction: AnyObject {
    func beforeCloudDeletion()
}

extension Cloudable where Self: Object {
    var className: String { return Self.className() }
    
    public static var recordType: String {
        return className()
    }
    
    public var recordType: String {
        return Self.recordType
    }
    
    private var primaryKeyPropertyName: String {
        guard let sharedSchema = Self.sharedSchema() else {
            preconditionFailure("No schema found for object of type '\(recordType)'. Hint: Check implementation of the Object.")
        }
        
        guard let primaryKeyProperty = sharedSchema.primaryKeyProperty else {
            preconditionFailure("No primary key fround for object of type '\(recordType)'. Hint: Check implementation of the Object.")
        }
        
        return primaryKeyProperty.name
    }
    
    public var pkProperty: String {
        get {
            let propertyName = primaryKeyPropertyName
            guard let string = self[propertyName] as? String else {
                fatalError("The type of primary for object of type '\(recordType)' should be `String`. Hint: Check implementation of the Object.")
            }
            return string
        }
        set {
            let propertyName = primaryKeyPropertyName
            let id = newValue
            guard let _ = self[propertyName] as? String else {
                fatalError("The type of primary for object of type '\(recordType)' should be `String`. Hint: Check implementation of the Object.")
            }
            self[propertyName] = id
        }
    }
    
    public var nonSyncedProperties: [String] { return [] }
}
