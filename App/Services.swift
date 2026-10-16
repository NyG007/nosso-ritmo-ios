import SwiftUI
@preconcurrency import UserNotifications
import WidgetKit
import CloudKit

enum WidgetBridge {
    static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConfig.groupID)?.appendingPathComponent("snapshot.json")
    }
    static func write(_ snapshot: WidgetSnapshot) throws {
        guard let url = fileURL else { throw RhythmError.message("App Group indisponível. Confira a assinatura e os identificadores no Xcode.") }
        try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        WidgetCenter.shared.reloadAllTimelines()
    }
    static func clear() {
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

actor ReminderService {
    static let shared = ReminderService()
    func authorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }
    func update(events: [Occurrence], enabled: Bool, now: Date) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("ritmo-") }.map(\.identifier))
        guard enabled else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let reminders = events.filter { $0.record.reminderMinutes >= 0 && $0.start.addingTimeInterval(-Double($0.record.reminderMinutes) * 60) > now }
            .sorted { $0.start.addingTimeInterval(-Double($0.record.reminderMinutes) * 60) < $1.start.addingTimeInterval(-Double($1.record.reminderMinutes) * 60) }
        for event in reminders.prefix(60) {
            let content = UNMutableNotificationContent(); content.title = event.record.title
            content.body = "Um momento no Nosso Ritmo está chegando."; content.sound = .default
            content.userInfo = ["url": "nossoritmo://event/\(event.record.id.uuidString)?at=\(event.start.timeIntervalSince1970)"]
            let date = event.start.addingTimeInterval(-Double(event.record.reminderMinutes) * 60)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "ritmo-\(event.id)", content: content, trigger: trigger))
        }
    }
}

struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    let onChange: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }
    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: CKContainer(identifier: AppConfig.cloudID))
        controller.delegate = context.coordinator
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        return controller
    }
    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}
    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let onChange: () -> Void
        init(onChange: @escaping () -> Void) { self.onChange = onChange }
        func itemTitle(for csc: UICloudSharingController) -> String? { "Nosso Ritmo" }
        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            NotificationCenter.default.post(name: .rhythmError, object: error.localizedDescription)
        }
        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) { onChange() }
        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) { onChange() }
    }
}

extension Notification.Name {
    static let rhythmInvite = Notification.Name("rhythmInvite")
    static let rhythmError = Notification.Name("rhythmError")
    static let rhythmURL = Notification.Name("rhythmURL")
}
