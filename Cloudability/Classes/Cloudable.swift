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
    /// Defaultly the id of an object.
    var recordID: CKRecordID { get }
    /// Defaultly the `className()`.
    static var recordType: String { get }
    /// Defaultly the class name of an object.
    var recordType: String { get }
    
    /// Check if an item is deleted, used for soft deletion locally.
    ///
    /// It's also good for local change observation of deleted objects, Since **truly-deleted** objects are no longer found.
    var isDeleted: Bool { get set }
    
    var pkProperty: String { get set }
    
    func validate() -> Bool
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
    
    public var recordID: CKRecordID {
        let propertyName = primaryKeyPropertyName
        if let string = self[propertyName] as? String {
            return CKRecordID(recordName: string)
        }
        
        fatalError("The type of primary for object of type '\(recordType)' should be `String`. Hint: Check implementation of the Object.")
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
    
    public func validate() -> Bool {
        guard let sharedSchema = Self.sharedSchema() else {
            print("No schema found for object of type '\(recordType)'. Hint: Check implementation of the Object.")
            return false
        }
        
        guard let primaryKeyProperty = sharedSchema.primaryKeyProperty else {
            print("No primary key fround for object of type '\(recordType)'. Hint: Check implementation of the Object.")
            return false
        }
        
        guard let _ = self[primaryKeyProperty.name] as? String else {
            print("The type of primary for object of type '\(recordType)' should be `String`. Hint: Check implementation of the Object.")
            return false
        }
        
        return true
    }
}
