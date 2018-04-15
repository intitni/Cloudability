import UIKit
import RealmSwift
import Cloudability

protocol TestableObject {
    var description: String { get }
    var title: String { get }
}

class ViewController: UIViewController {

    let tableView = UITableView()
    
    let pilots = try! Realm().objects(Pilot.self)
    let mobileSuits = try! Realm().objects(MobileSuit.self)
    let battleShips = try! Realm().objects(BattleShip.self)
    
    var observations = [NotificationToken]()
    
    override func viewDidLoad() {
        super.viewDidLoad()
    
        observeLists()
        view.addSubview(tableView)
        tableView.frame = self.view.frame
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.delegate = self
        tableView.dataSource = self
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    func observeLists() {
        self.observations.append(pilots.observe({ [weak self] _ in self?.tableView.reloadData()}))
        self.observations.append(mobileSuits.observe({ [weak self] _ in self?.tableView.reloadData()}))
        self.observations.append(battleShips.observe({ [weak self] _ in self?.tableView.reloadData()}))
    }
}

extension ViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 3
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.textLabel?.text = {
            let row = indexPath.row
            switch row {
            case 0:
                return "Pilots: \(pilots.count)"
            case 1:
                return "Mobile Suits: \(mobileSuits.count)"
            case 2:
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
            navigationController?.pushViewController(ListViewController<Pilot>(list: pilots), animated: true)
        case 1:
            navigationController?.pushViewController(ListViewController<MobileSuit>(list: mobileSuits), animated: true)
        case 2:
            navigationController?.pushViewController(ListViewController<BattleShip>(list: battleShips), animated: true)
        default: return
        }
    }
}

