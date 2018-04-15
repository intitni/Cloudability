import UIKit
import RealmSwift

class DetailViewController<ObjectType: Object & TestableObject>: UIViewController {
    let object: ObjectType
    let textView = UITextView()
    var observation: NotificationToken!
    
    init(object: ObjectType) {
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
        let addButton = UIBarButtonItem(title: "Add", style: .plain, target: self, action: #selector(handleAddButtonTap))
        navigationItem.rightBarButtonItems = [addButton]
    }
    
    @objc func handleAddButtonTap() {
        switch ObjectType.self {
        case is MobileSuit.Type:
            let alert = UIAlertController(title: "Add Pilot", message: nil, preferredStyle: .alert)
            alert.addTextField {
                $0.accessibilityLabel = "name"
                $0.placeholder = "name"
            }
            alert.addTextField {
                $0.accessibilityLabel = "age"
                $0.placeholder = "age"
                $0.keyboardType = .numberPad
            }
            let save = UIAlertAction(title: "Add", style: .default) { action in
                guard let name = alert.textFields?.filter({ $0.accessibilityLabel == "name" }).first,
                    let age = alert.textFields?.filter({ $0.accessibilityLabel == "age" }).first,
                    let n = name.text, let a = Int(age.text ?? ""), !n.isEmpty else { return }
                let pilot = Pilot(name: n, age: a)
                let realm = try! Realm()
                try? realm.write {
                    if let object = self.object as? MobileSuit {
                        pilot.piloting = object
                    }
                    realm.add(pilot)
                }
            }
            alert.addAction(save)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            present(alert, animated: true, completion: nil)
        case is BattleShip.Type:
            let alert = UIAlertController(title: "Add Mobile Suit", message: nil, preferredStyle: .alert)
            alert.addTextField {
                $0.accessibilityLabel = "type"
                $0.placeholder = "type"
            }
            let save = UIAlertAction(title: "Add", style: .default) { action in
                guard let type = alert.textFields?.filter({ $0.accessibilityLabel == "type" }).first,
                    let t = type.text, !t.isEmpty else { return }
                let suit = MobileSuit(type: t)
                let realm = try! Realm()
                try? realm.write {
                    if let object = self.object as? BattleShip {
                        suit.onShip = object
                    }
                    realm.add(suit)
                }
            }
            alert.addAction(save)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            present(alert, animated: true, completion: nil)
        default:
            let alert = UIAlertController(title: "Nothing to add to a pilot", message: nil, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Fine", style: .cancel))
            present(alert, animated: true, completion: nil)
        }
    }}
