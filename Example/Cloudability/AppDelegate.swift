import UIKit
import RealmSwift
import Cloudability
import CloudKit

let container = Container(identifier: "iCloud.org.cocoapods.demo.Cloudability-Example.Custom")
let cloud = Cloud(container: container, zoneType: .sameZone("zone"))

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?


    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // excluding Cloudability objects
        Realm.Configuration.defaultConfiguration.objectTypes = [
            Pilot.self,
            MobileSuit.self,
            BattleShip.self
        ]
        
        application.registerForRemoteNotifications()
        cloud.switchOn { error in
            print(error?.localizedDescription ?? "Switched on!")
        }
 
        return true
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        
        let dict = userInfo as! [String: NSObject]
        guard let _ = CKNotification(fromRemoteNotificationDictionary:dict) as? CKDatabaseNotification else { return }
        
        cloud.pull { error in
            if error == nil {
                completionHandler(.newData)
            } else {
                completionHandler(.failed)
            }
        }
        
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        
    }


}

