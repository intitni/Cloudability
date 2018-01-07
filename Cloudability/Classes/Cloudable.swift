//
//  Cloudable.swift
//  Cloudability
//
//  Created by Shangxin Guo on 03/12/2017.
//

import Foundation
import RealmSwift
import CloudKit

public typealias CloudableObject = Object & Cloudable

public protocol Cloudable: class {
    
    static var zoneID: CKRecordZoneID { get }
    var zoneID: CKRecordZoneID { get }
    
    /// Defaultly the `className()`.
    static var recordType: String { get }
    /// Defaultly the class name of an object.
    var recordType: String { get }
    
    var recordID: CKRecordID { get }
    var pkProperty: String { get set }
}

extension Cloudable where Self: Object  {
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
    
    public static var zoneID: CKRecordZoneID {
        return CKRecordZoneID(zoneName: recordType, ownerName: CKCurrentUserDefaultName)
    }
    
    public var zoneID: CKRecordZoneID {
        return Self.zoneID
    }
    
    public var recordID: CKRecordID {
        return CKRecordID(recordName: pkProperty, zoneID: zoneID)
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
}
