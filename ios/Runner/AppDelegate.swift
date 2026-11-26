import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "little_farm/daily_login_reminder", binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { [weak self] call, result in
        guard call.method == "enable" else {
          result(FlutterMethodNotImplemented)
          return
        }
        self?.enableDailyReminder()
        result(nil)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func enableDailyReminder() {
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      switch settings.authorizationStatus {
      case .notDetermined:
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
          if granted { self.scheduleDailyReminder(center) }
        }
      case .authorized, .provisional:
        self.scheduleDailyReminder(center)
      default:
        break
      }
    }
  }

  private func scheduleDailyReminder(_ center: UNUserNotificationCenter) {
    let content = UNMutableNotificationContent()
    content.title = "Login diário · Little Farm"
    content.body = "Abra a fazenda para manter sua sequência de recompensas."
    content.sound = .default
    var time = DateComponents()
    time.timeZone = TimeZone(identifier: "America/Sao_Paulo")
    time.hour = 20
    time.minute = 0
    center.add(UNNotificationRequest(
      identifier: "daily_login", content: content,
      trigger: UNCalendarNotificationTrigger(dateMatching: time, repeats: true)
    ))
  }
}
