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
    let textView = UITextView()
    var observation: NotificationToken!
    
    init(object: Object & TestableObject) {
        self.object = object
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        observation.invalidate()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.addSubview(textView)
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        NSLayoutConstraint.activate([
            textView.leftAnchor.constraint(equalTo: view.leftAnchor),
            textView.topAnchor.constraint(equalTo: view.topAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            textView.rightAnchor.constraint(equalTo: view.rightAnchor),
            ])
        textView.text = object.description
        observation = object.observe { [unowned self] _ in
            self.textView.text = self.object.description
        }
    }

}
