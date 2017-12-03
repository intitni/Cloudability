//
//  ObjectConverter.swift
//  BestBefore
//
//  Created by Shangxin Guo on 12/11/2017.
//  Copyright © 2017 Inti Guo. All rights reserved.
//

import RealmSwift
import CloudKit

func realmObjectType(forName name: String) -> Object.Type {
    if let objClass = NSClassFromString(name) {
        return objClass as! Object.Type
    } else {
        let namespace = Bundle.main.infoDictionary!["CFBundleExecutable"] as! String
        return NSClassFromString("\(namespace.replacingOccurrences(of: " ", with: "_")).\(name)") as! Object.Type
    }
}

class ObjectConverter {
    func convert(_ object: CloudableObject) -> CKRecord {
        let propertyList = object.objectSchema.properties
        let recordID = object.recordID
        let record = CKRecord(recordType: object.recordType, recordID: recordID)
        
        for property in propertyList {
            record[property.name] = convert(property, of: object)
        }
        record["schemaVersion"] = NSNumber(value: store.realm.configuration.schemaVersion)
        
        return record
    }
    
    func convert(_ record: CKRecord) -> (CloudableObject, [PendingRelationship]) {
        let (recordType, id) = (record.recordType, record.recordID.recordName)
        let type = realmObjectType(forName: recordType)
        let object = type.init() as! CloudableObject
        
        var pendingRelationships = [PendingRelationship]()
        object.pkProperty = id
        
        let propertyList = object.objectSchema.properties
        for property in propertyList where property.name != type.primaryKey() {
            let recordValue = record[property.name]
            
            let isOptional = property.isOptional
            switch property.type {
            case .int:
                object[property.name] = isOptional
                    ? recordValue?.int
                    : recordValue?.int ?? 0
            case .bool:
                object[property.name] = isOptional
                    ? recordValue?.bool
                    : recordValue?.bool ?? false
            case .float:
                object[property.name] = isOptional
                    ? recordValue?.float
                    : recordValue?.float ?? 0
            case .double:
                object[property.name] = isOptional
                    ? recordValue?.double
                    : recordValue?.double ?? 0
            case .string:
                object[property.name] = isOptional
                    ? recordValue?.string
                    : recordValue?.string ?? ""
            case .data:
                object[property.name] = isOptional
                    ? recordValue?.data
                    : recordValue?.data ?? Data()
            case .any:
                object[property.name] = recordValue
            case .date:
                object[property.name] = isOptional
                    ? recordValue?.date
                    : recordValue?.date ?? Date()
                
            // when things a relationship
            case .object:
                if !property.isArray {
                    let relationship: PendingRelationship = {
                        let p = PendingRelationship()
                        p.fromType = recordType
                        p.fromIdentifier = id
                        p.toType = property.objectClassName!
                        p.propertyName = property.name
                        if let id = recordValue?.string {
                            p.targetIdentifiers.append(id)
                        }
                        return p
                    }()
                    pendingRelationships.append(relationship)
                } else {
                    guard let recordValue = recordValue else { break }
                    let ids = recordValue.list as! [String]
                    let relationship: PendingRelationship = {
                        let p = PendingRelationship()
                        p.fromType = recordType
                        p.fromIdentifier = id
                        p.toType = property.objectClassName!
                        p.propertyName = property.name
                        p.targetIdentifiers.append(objectsIn: ids)
                        return p
                    }()
                    pendingRelationships.append(relationship)
                }
            case .linkingObjects: break // ignored
            }
        }
        
        return (object, pendingRelationships)
    }
    
    private func convert(_ property: Property, of object: Object) -> CKRecordValue? {
        guard let value = object.value(forKey: property.name) else { return nil }
        
        switch property.type {
        case .int:    return (value as? Int).map(NSNumber.init(value:))
        case .bool:   return (value as? Bool).map(NSNumber.init(value:))
        case .float:  return (value as? Float).map(NSNumber.init(value:))
        case .double: return (value as? Double).map(NSNumber.init(value:))
        case .string: return value as? String as CKRecordValue?
        case .data:   return (value as? Data).map(NSData.init(data:))
        case .any:    return value as? CKRecordValue
        case .date:   return value as? Date as CKRecordValue?
            
        case .object:
            if !property.isArray {
                guard let object = value as? CloudableObject
                    else { return nil }
                return object.pkProperty as CKRecordValue
            } else {
                let className = property.objectClassName!
                let ownerType = realmObjectType(forName: className)
                let list = object.dynamicList(property.name)
                guard let ownerPrimaryKey = ownerType.primaryKey() else { return nil }
                let ids = list.flatMap { $0[ownerPrimaryKey] as? String }
                return ids as NSArray
            }
        case .linkingObjects: return nil
        }
    }
}

extension CKRecordValue {
    var date: Date? {
        return self as? NSDate as Date?
    }
    
    var bool: Bool? {
        return (self as? NSNumber)?.boolValue
    }
    
    var int: Int? {
        return (self as? NSNumber)?.intValue
    }
    
    var double: Double? {
        return (self as? NSNumber)?.doubleValue
    }
    
    var float: Float? {
        return (self as? NSNumber)?.floatValue
    }
    
    var string: String? {
        return self as? String
    }
    
    var data: Data? {
        return (self as? NSData).map(Data.init(referencing:))
    }
    
    var asset: CKAsset? {
        return self as? CKAsset
    }
    
    var location: CLLocation? {
        return self as? CLLocation
    }
    
    var list: Array<Any>? {
        guard let array = self as? NSArray else { return nil }
        return Array(array)
    }
}

