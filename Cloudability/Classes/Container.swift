//
//  Container.swift
//  Cloudability
//
//  Created by Shangxin Guo on 2018/4/15.
//

import CloudKit
import PromiseKit

public class Container {
    let ckContainer: CKContainer
    let privateCloudDatabase: Database
    let publicCloudDatabase: Database
    let sharedCloudDatabase: Database
    
    public convenience init(identifier: String) {
        self.init(container: CKContainer(identifier: identifier))
    }
    
    public init(container: CKContainer) {
        self.ckContainer = container
        privateCloudDatabase = Database(database: container.privateCloudDatabase)
        publicCloudDatabase = Database(database: container.publicCloudDatabase)
        sharedCloudDatabase = Database(database: container.sharedCloudDatabase)
    }
    
    public class func `default`() -> Container {
        return Container(container: .default())
    }
    
    public var containerIdentifier: String? { return ckContainer.containerIdentifier }
    
    
    public func add(_ operation: CKOperation) {
        ckContainer.add(operation)
    }
}

public extension Container {
    func accountStatus() -> Promise<CKAccountStatus> {
        return ckContainer.accountStatus()
    }
    
    func fetchAllLongLivedOperationIDs(completionHandler: @escaping ([String]?, Error?)->Void) {
        ckContainer.fetchAllLongLivedOperationIDs(completionHandler: completionHandler)
    }
    
    func fetchAllLongLivedOperationIDs() -> Promise<[String]?> {
        return Promise { fetchAllLongLivedOperationIDs(completionHandler: $0.resolve) }
    }
    
    func fetchLongLivedOperation(withID id: String, completionHandler: @escaping (CKOperation?, Error?)->Void) {
        ckContainer.fetchLongLivedOperation(withID: id, completionHandler: completionHandler)
    }
    
    func fetchLongLivedOperation(withID id: String) -> Promise<CKOperation?> {
        return Promise { fetchLongLivedOperation(withID: id, completionHandler: $0.resolve) }
    }
}
