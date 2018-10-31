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
        case is BattleShip.Type:
            let alert = UIAlertController(title: "Add Battle Ship", message: nil, preferredStyle: .alert)
            alert.addTextField {
                $0.accessibilityLabel = "number"
                $0.placeholder = "number of catapults"
                $0.keyboardType = .numberPad
            }
            alert.addTextField {
                $0.accessibilityLabel = "type"
                $0.placeholder = "name"
            }
            let save = UIAlertAction(title: "Add", style: .default) { action in
                guard let number = alert.textFields?.filter({ $0.accessibilityLabel == "number" }).first,
                    let type = alert.textFields?.filter({ $0.accessibilityLabel == "type" }).first,
                    let t = type.text, let n = Int(number.text ?? ""), !t.isEmpty else { return }
                let ship = BattleShip(name: t, msCatapults: n)
                let realm = try! Realm()
                try? realm.write {
                    realm.add(ship)
                }
            }
            alert.addAction(save)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            present(alert, animated: true, completion: nil)
        default:
            let alert = UIAlertController(title: "You can only add in BattleShip list", message: "To add pilots and mobile suits, go to detail view.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .cancel))
            present(alert, animated: true, completion: nil)
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
    
    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        return .delete
    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard case .delete = editingStyle else { return }
        let object = list[indexPath.row]
        let realm = try! Realm()
        try! realm.write {
            realm.delete(cloudableObject: object)
        }
    }
}

