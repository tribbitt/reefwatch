import Foundation
import Combine
import SwiftUI
import UserNotifications

/// Local-notification scheduler that fires when a station crosses a DHW threshold
/// upward between two refreshes.
///
/// This is intentionally device-local: we have no backend / APNs token, so "push"
/// means a UNNotificationRequest scheduled in response to a freshly-fetched ERDDAP
/// reading. If you later add a server, replace `evaluate(_:)` with a server-side
/// comparison and APNs send — the rest of the app stays unchanged.
@MainActor
final class NotificationService: ObservableObject {
    static let shared = NotificationService()

    // MARK: - Persisted preferences

    @AppStorage("notifications.enabled")    var isEnabled: Bool = false
    @AppStorage("notifications.threshold")  var thresholdDHW: Double = 4.0   // Alert Level 1

    /// Last DHW value we observed per station ID, JSON-encoded in UserDefaults.
    @AppStorage("notifications.lastSeenDHW") private var lastSeenJSON: String = "{}"

    // MARK: - Authorization

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private init() {
        Task { await refreshAuthorizationStatus() }
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        self.authorizationStatus = settings.authorizationStatus
    }

    /// Returns true if authorization was granted (or already granted).
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationStatus()
            return granted
        } catch {
            return false
        }
    }

    /// User-facing toggle. When flipping ON for the first time we request auth.
    func setEnabled(_ value: Bool) async {
        if value && authorizationStatus != .authorized {
            let granted = await requestAuthorization()
            isEnabled = granted
        } else {
            isEnabled = value
        }
    }

    // MARK: - Evaluation

    /// Walks the current ranking and fires a notification for any station whose
    /// DHW crossed the user-configured threshold upward since the last refresh.
    func evaluate(_ ranking: [RankedReef]) async {
        guard isEnabled, authorizationStatus == .authorized else {
            // Still update last-seen so toggling on later doesn't fire a flood of stale crossings.
            persistLastSeen(from: ranking)
            return
        }

        var lastSeen = readLastSeen()
        let threshold = thresholdDHW

        for reef in ranking {
            let prev = lastSeen[reef.id]                // nil = first observation
            let crossedUp = (prev ?? Double.greatestFiniteMagnitude) < threshold && reef.currentDHW >= threshold

            if crossedUp {
                await schedule(for: reef)
            }
            lastSeen[reef.id] = reef.currentDHW
        }

        writeLastSeen(lastSeen)
    }

    // MARK: - Scheduling

    private func schedule(for reef: RankedReef) async {
        let content = UNMutableNotificationContent()
        content.title = "Thermal stress alert: \(reef.station.name)"
        content.body  = String(
            format: "DHW just crossed %.0f °C·weeks (now %.1f, %@).",
            thresholdDHW,
            reef.currentDHW,
            reef.alertLevel.rawValue,
            reef.streakWeeks,
            reef.streakWeeks == 1 ? "week" : "weeks"
        )
        content.sound = .default
        content.userInfo = ["stationId": reef.id]

        // Fire ~immediately. UNUserNotificationCenter requires a trigger; 1s is fine.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "crw.alert.\(reef.id).\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: trigger
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Last-seen persistence

    private func readLastSeen() -> [String: Double] {
        guard let data = lastSeenJSON.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: Double].self, from: data)
        else { return [:] }
        return dict
    }

    private func writeLastSeen(_ dict: [String: Double]) {
        if let data = try? JSONEncoder().encode(dict),
           let str = String(data: data, encoding: .utf8) {
            lastSeenJSON = str
        }
    }

    private func persistLastSeen(from ranking: [RankedReef]) {
        var dict = readLastSeen()
        for reef in ranking { dict[reef.id] = reef.currentDHW }
        writeLastSeen(dict)
    }
}
