//
//  Cloudable.swift
//  Cloudability
//
//  Created by Shangxin Guo on 03/12/2017.
//

import Foundation
import RealmSwift

typealias CloudableObject = Object & Cloudable

protocol Cloudable: class {
    var id: String { get set }
    var typeName: String { get }
}

extension Cloudable where Self: Object  {
    var typeName: String {
        return type(of: self).className()
    }
}
