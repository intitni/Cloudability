//
//  OhListViewController.swift
//  Cloudability_Example
//
//  Created by Shangxin Guo on 14/01/2018.
//  Copyright © 2018 CocoaPods. All rights reserved.
//

import UIKit
import RealmSwift
import Cloudability

class ListViewController<ObjectType: CloudableObject & TestableObject>: UIViewController, UITableViewDelegate, UITableViewDataSource {
    let tableView = UITableView()
    let list: Results<ObjectType>
    var observation: NotificationToken!
    
    init(list: Results<ObjectType>) {
        self.list = list
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
        view.addSubview(tableView)
        tableView.frame = self.view.frame
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.delegate = self
        tableView.dataSource = self
        observation = list.observe { [unowned self] _ in
            self.tableView.reloadData()
        }
        let addButton = UIBarButtonItem(title: "Add", style: .plain, target: self, action: #selector(handleAddButtonTap))
        navigationItem.rightBarButtonItems = [addButton]
    }
    
    @objc func handleAddButtonTap() {
        switch ObjectType.self {
        case is Pilot.Type: break
        case is MobileArmor.Type: break
        case is MobileSuit.Type: break
        case is BattleShip.Type: break
        default: break
        }
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return list.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let object = list[indexPath.row]
        cell.textLabel?.text = object.title
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let object = list[indexPath.row]
        navigationController?.pushViewController(DetailViewController(object: object), animated: true)
    }
    
    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCellEditingStyle {
        return .delete
    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        guard case .delete = editingStyle else { return }
        let object = list[indexPath.row]
        try! Realm().delete(cloudableObject: object)
    }
}

