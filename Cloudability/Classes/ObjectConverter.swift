//
//  ObjectConverter.swift
//  BestBefore
//
//  Created by Shangxin Guo on 12/11/2017.
//  Copyright © 2017 Inti Guo. All rights reserved.
//

import RealmSwift
import Realm
import CloudKit

func realmObjectType(forName name: String) -> Object.Type? {
    return RLMSchema.class(for: name) as? Object.Type // let Realm do the job
}

class ObjectConverter {
    let zoneType: ZoneType
    
    init(zoneType: ZoneType) {
        self.zoneType = zoneType
    }
    
    func zoneID(for objectType: CloudableObject.Type) -> CKRecordZoneID {
        switch zoneType {
        case .individualForEachRecordType:
            return CKRecordZoneID(zoneName: objectType.recordType, ownerName: CKCurrentUserDefaultName)
        case .customRule(let rule):
            return rule(objectType)
        case .defaultZone:
            return CKRecordZone.default().zoneID
        case .sameZone(let name):
            return CKRecordZoneID(zoneName: name, ownerName: CKCurrentUserDefaultName)
        }
    }
    
    func recordID(for object: CloudableObject) -> CKRecordID {
        let className = object.className
        let objClass = realmObjectType(forName: className)!
        let objectClass = objClass as! CloudableObject.Type
        return CKRecordID(recordName: object.pkProperty, zoneID: zoneID(for: objectClass))
    }
    
    func convert(_ object: CloudableObject) -> CKRecord {
        let propertyList = object.objectSchema.properties
        let recordID = self.recordID(for: object)
        let record = CKRecord(recordType: object.recordType, recordID: recordID)
        let nonSyncedProperties = object.nonSyncedProperties
        
        for property in propertyList where !nonSyncedProperties.contains(property.name) {
            record[property.name] = convert(property, of: object)
        }
        let realm = try! Realm()
        record["schemaVersion"] = NSNumber(value: realm.configuration.schemaVersion)
        
        return record
    }
    
    func convert(_ record: CKRecord) -> (CloudableObject, [PendingRelationship]) {
        let (recordType, id) = (record.recordType, record.recordID.recordName)
        let type = realmObjectType(forName: recordType) as! CloudableObject.Type
        let object = type.init()
        
        var pendingRelationships = [PendingRelationship]()
        object.pkProperty = id
        let nonSyncedProperties = object.nonSyncedProperties
        
        let propertyList = object.objectSchema.properties
        for property in propertyList where property.name != type.primaryKey() && !nonSyncedProperties.contains(property.name) {
            let recordValue = record[property.name]
            
            let isOptional = property.isOptional
            let isArray = property.isArray
            switch property.type {
            case .int:
                object[property.name] =
                    isArray
                    ? (recordValue as? [Int]) ?? [Int]()
                    : isOptional
                        ? recordValue?.int
                        : recordValue?.int ?? 0
            case .bool:
                object[property.name] =
                    isArray
                    ? (recordValue as? [Bool]) ?? [Bool]()
                    : isOptional
                        ? recordValue?.bool
                        : recordValue?.bool ?? false
            case .float:
                object[property.name] =
                    isArray
                    ? (recordValue as? [Float]) ?? [Float]()
                    : isOptional
                        ? recordValue?.float
                        : recordValue?.float ?? 0
            case .double:
                object[property.name] =
                    isArray
                    ? (recordValue as? [Double]) ?? [Double]()
                    : isOptional
                        ? recordValue?.double
                        : recordValue?.double ?? 0
            case .string:
                object[property.name] =
                    isArray
                    ? (recordValue as? [String]) ?? [String]()
                    : isOptional
                    ? recordValue?.string
                    : recordValue?.string ?? ""
            case .data:
                object[property.name] =
                    isArray
                    ? (recordValue as? [Data]) ?? [Data]()
                    : isOptional
                        ? recordValue?.data
                        : recordValue?.data ?? Data()
            case .any:
                object[property.name] = recordValue
            case .date:
                object[property.name] =
                    isArray
                    ? (recordValue as? [Date]) ?? [Date]()
                    : isOptional
                        ? recordValue?.date
                        : recordValue?.date ?? Date()
                
            // when things a relationship
            case .object:
                let className = property.objectClassName!
                let targetType = realmObjectType(forName: className)!
                guard let _ = targetType as? CloudableObject.Type else { break }
                if isArray {
                    guard let recordValue = recordValue else { break }
                    let ids = (recordValue.list as! [CKReference]).map { $0.recordID.recordName }
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
                } else {
                    let relationship: PendingRelationship = {
                        let p = PendingRelationship()
                        p.fromType = recordType
                        p.fromIdentifier = id
                        p.toType = property.objectClassName!
                        p.propertyName = property.name
                        if let id = recordValue?.reference?.recordID.recordName {
                            p.targetIdentifiers.append(id)
                        }
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
        let isArray = property.isArray

        switch property.type {
        case .int, .bool, .float, .double, .string, .any, .date, .data:
            return value as? CKRecordValue
        case .object:
            let className = property.objectClassName!
            let targetType = realmObjectType(forName: className)!
            
            // Object that is not Cloudable will be ignored.
            guard let type = targetType as? CloudableObject.Type else { return nil }
            let targetZoneID = zoneID(for: type)
            if !isArray {
                guard let object = value as? CloudableObject
                    else { return nil }
                return CKReference(recordID: CKRecordID(recordName: object.pkProperty, zoneID: targetZoneID), action: .none)
            } else {
                let list = object.dynamicList(property.name)
                guard let targetPrimaryKey = targetType.primaryKey() else { return nil }
                let all = list
                    .compactMap { $0.value(forKey: targetPrimaryKey) as? String }
                    .map { CKReference(recordID: CKRecordID(recordName: $0, zoneID: targetZoneID), action: .none) }
                let ids = Array(all)
                if ids.isEmpty { return nil }
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
    
    var reference: CKReference? {
        return self as? CKReference
    }
}

