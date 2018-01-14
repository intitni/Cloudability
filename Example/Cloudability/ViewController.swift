//
//  ViewController.swift
//  Cloudability
//
//  Created by int123c on 12/03/2017.
//  Copyright (c) 2017 int123c. All rights reserved.
//

import UIKit
import RealmSwift
import Cloudability

protocol TestableObject {
    var description: String { get }
    var title: String { get }
}

//let cloud = Cloud(containerIdentifier: "iCloud.org.cocoapods.demo.Cloudability-Example.Custom")

class ViewController: UIViewController {

    let tableView = UITableView()
    
    let pilots = try! Realm().objects(Pilot.self)
    let mobileArmors = try! Realm().objects(MobileArmor.self)
    let mobileSuits = try! Realm().objects(MobileSuit.self)
    let battleShips = try! Realm().objects(BattleShip.self)
    
    var observations = [NotificationToken]()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        generateInitialData()
        observeLists()
        self.view.addSubview(tableView)
        tableView.frame = self.view.frame
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.delegate = self
        tableView.dataSource = self
    }
    
    func generateInitialData() {
        let realm = try! Realm()
        let flag = UserDefaults.standard.bool(forKey: "LaunchedOnce")
        guard flag else { return }
        
        let tim = Pilot(name: "Tim", age: 21)
        let john = Pilot(name: "John", age: 24)
        let sarah = Pilot(name: "Sarah", age: 30)
        
        let gundam = MobileSuit(type: "ZZZ", pilot: tim)
        let armor = MobileArmor(type: "AAA", numberOfPilotsNeeded: 2, pilots: [john, tim])
        
        let battleShip = BattleShip(name: "Ship", msCatapults: 4, mobileSuits: [gundam], mobileArmors: [armor])
        
        try? realm.write {
            realm.add(tim)
            realm.add(john)
            realm.add(sarah)
            realm.add(gundam)
            realm.add(armor)
            realm.add(battleShip)
        }
        
        UserDefaults.standard.set(true, forKey: "LaunchedOnce")
    }
    
    func observeLists() {
        self.observations.append(pilots.observe({ [weak self] _ in self?.tableView.reloadData()}))
        self.observations.append(mobileArmors.observe({ [weak self] _ in self?.tableView.reloadData()}))
        self.observations.append(mobileSuits.observe({ [weak self] _ in self?.tableView.reloadData()}))
        self.observations.append(battleShips.observe({ [weak self] _ in self?.tableView.reloadData()}))
    }
}

extension ViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 4
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.textLabel?.text = {
            let row = indexPath.row
            switch row {
            case 0:
                return "Pilots: \(pilots.count)"
            case 1:
                return "Mobile Armors: \(mobileArmors.count)"
            case 2:
                return "Mobile Suits: \(mobileSuits.count)"
            case 3:
                return "Battle Ships: \(battleShips.count)"
            default: return nil
            }
        }()
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let row = indexPath.row
        switch row {
        case 0:
            present(ListViewController<Pilot>(list: pilots), animated: true, completion: nil)
        case 1:
            present(ListViewController<MobileArmor>(list: mobileArmors), animated: true, completion: nil)
        case 2:
            present(ListViewController<MobileSuit>(list: mobileSuits), animated: true, completion: nil)
        case 3:
            present(ListViewController<BattleShip>(list: battleShips), animated: true, completion: nil)
        default: return
        }
    }
}

