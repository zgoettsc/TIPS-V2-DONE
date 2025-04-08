import SwiftUI
import FirebaseCore
import UserNotifications

@main
struct TIPsApp: App {
    @StateObject private var appData = AppData()
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        FirebaseApp.configure()
        setupNotifications()
        UIApplication.shared.delegate = AppDelegate.shared
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(appData: appData)
                .onChange(of: scenePhase) { newPhase in
                    switch newPhase {
                    case .active:
                        print("App became active")
                        appData.logToFile("App became active")
                    case .inactive:
                        print("App became inactive")
                        appData.logToFile("App became inactive")
                        appData.saveTimerState()
                    case .background:
                        print("App moved to background")
                        appData.logToFile("App moved to background")
                        appData.saveTimerState()
                    @unknown default:
                        print("Unknown scene phase")
                        appData.logToFile("Unknown scene phase")
                    }
                }
        }
    }
    
    func setupNotifications() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Error requesting notification permission: \(error)")
            } else {
                print("Notification permission \(granted ? "granted" : "denied")")
            }
        }
        
        let okayAction = UNNotificationAction(identifier: "OKAY", title: "Okay", options: [.foreground])
        let snoozeAction = UNNotificationAction(identifier: "SNOOZE", title: "Snooze for 5 min", options: [])
        let treatmentCategory = UNNotificationCategory(
            identifier: "TREATMENT_TIMER",
            actions: [okayAction, snoozeAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        let reminderCategory = UNNotificationCategory(
            identifier: "REMINDER_CATEGORY",
            actions: [UNNotificationAction(identifier: "DISMISS", title: "Dismiss", options: [])],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([treatmentCategory, reminderCategory])
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    static let shared = AppDelegate()
    var appData: AppData = AppData()
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        return true
    }
}

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let appData = (UIApplication.shared.delegate as? AppDelegate)?.appData ?? AppData()
        if response.notification.request.identifier.contains("treatment_timer_") {
            switch response.actionIdentifier {
            case "SNOOZE":
                appData.treatmentTimerEnd = Date().addingTimeInterval(300)
                appData.treatmentTimerId = "treatment_timer_\(UUID().uuidString)"
                scheduleSnoozeNotifications(appData: appData)
                print("Snoozed timer for 5 minutes, id: \(appData.treatmentTimerId!)")
            case "OKAY", UNNotificationDefaultActionIdentifier:
                appData.treatmentTimerEnd = nil
                appData.treatmentTimerId = nil
                center.removeAllPendingNotificationRequests() // Clear any remaining repeats
                print("Dismissed timer via Okay or tap")
            default:
                print("Unknown action: \(response.actionIdentifier)")
            }
            print("User action: \(response.actionIdentifier) for \(response.notification.request.identifier)")
        }
        completionHandler()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        print("Will present notification: \(notification.request.identifier)")
        if notification.request.identifier.contains("treatment_timer_") {
            if UIApplication.shared.applicationState == .active {
                print("Foreground notification suppressed")
                completionHandler([])
            } else {
                print("Background notification with persistent banner and sound")
                completionHandler([.banner, .sound, .badge, .list])
            }
        } else {
            completionHandler([.banner, .sound, .badge, .list])
        }
    }
    
    private func scheduleSnoozeNotifications(appData: AppData) {
        let center = UNUserNotificationCenter.current()
        let baseId = appData.treatmentTimerId!
        
        for i in 0..<4 { // Repeat 4 times, 1 second apart
            let content = UNMutableNotificationContent()
            content.title = "Time for the next treatment food"
            content.body = "Your 5-minute snooze has ended."
            content.sound = UNNotificationSound.default // Closest match to SystemSoundID(1005)
            content.categoryIdentifier = "TREATMENT_TIMER"
            content.interruptionLevel = .timeSensitive
            content.threadIdentifier = "treatment-timer-thread-\(baseId)"
            
            let delay = 300.0 + Double(i) // 300s base + 0,1,2,3s for repeats
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(delay, 1), repeats: false)
            let request = UNNotificationRequest(identifier: "\(baseId)_repeat_\(i)", content: content, trigger: trigger)
            
            center.add(request) { error in
                if let error = error {
                    print("Error scheduling snooze repeat \(i): \(error)")
                } else {
                    print("Scheduled snooze repeat \(i) for \(delay)s, id: \(request.identifier)")
                }
            }
        }
    }
}
