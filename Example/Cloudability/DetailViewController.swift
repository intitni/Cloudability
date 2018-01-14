//
//  DetailViewController.swift
//  Cloudability_Example
//
//  Created by Shangxin Guo on 14/01/2018.
//  Copyright © 2018 CocoaPods. All rights reserved.
//

import UIKit
import RealmSwift

class DetailViewController: UIViewController {
    let object: Object & TestableObject
    
    init(object: Object & TestableObject) {
        self.object = object
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }

}
