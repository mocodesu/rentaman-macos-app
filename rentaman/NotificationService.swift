import Foundation
import UserNotifications
import SwiftData
import Observation

/// Schedules and manages all local notifications:
///   • Due-soon reminders (N days before) for unpaid bills
///   • Due-day reminders for unpaid bills
///   • Weekly summary (Sunday 9 AM) if enabled
///
/// Uses `UNCalendarNotificationTrigger` so reminders fire even when the
/// app is closed. Every reschedule rebuilds the full schedule from
/// scratch — cheap, and guarantees no stale notifications.
@Observable
final class NotificationService {
    static let shared = NotificationService()
    private init() {}

    // MARK: - State
    var authorizationStatus: UNAuthorizationStatus = .notDetermined
    var scheduledCount: Int = 0

    var isEnabled: Bool {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    var statusDescription: String {
        switch authorizationStatus {
        case .authorized:    return "Enabled"
        case .provisional:   return "Provisional"
        case .ephemeral:     return "Ephemeral"
        case .denied:        return "Denied"
        case .notDetermined: return "Not yet requested"
        @unknown default:    return "Unknown"
        }
    }

    // MARK: - Identifiers
    private static let dueSoonPrefix = "rentaman.bill.dueSoon."
    private static let dueDayPrefix  = "rentaman.bill.dueDay."
    private static let weeklySummaryId = "rentaman.weeklySummary"
    private static let categoryId = "RENTAMAN_BILL"

    /// Cap the number of bills we schedule for. macOS allows 64 pending
    /// notifications per app; each bill generates up to 2.
    private static let maxTrackedBills = 30

    /// Time of day to fire reminders (local time).
    private static let reminderHour = 9
    private static let reminderMinute = 0

    private let center = UNUserNotificationCenter.current()
    private var rescheduleTask: Task<Void, Never>?

    // MARK: - Bootstrap
    /// Called once from `RentaManApp.onAppear`.
    func bootstrap() async {
        await refreshAuthorizationStatus()
    }

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        await MainActor.run { self.authorizationStatus = settings.authorizationStatus }
    }

    /// Request permission. Returns `true` if granted.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationStatus()
            return granted
        } catch {
            print("❌ [Notifications] Authorization request failed: \(error)")
            await refreshAuthorizationStatus()
            return false
        }
    }

    // MARK: - Debounced reschedule
    /// Call this from anywhere data changes. Coalesces rapid calls into
    /// a single rebuild 0.8 s later.
    func scheduleReschedule(context: ModelContext) {
        rescheduleTask?.cancel()
        rescheduleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.reschedule(context: context)
        }
    }

    // MARK: - Reschedule (full rebuild)
    @MainActor
    func reschedule(context: ModelContext) async {
        await refreshAuthorizationStatus()

        // Always start clean — remove every notification we own.
        await removeAllOurNotifications()

        guard isEnabled else {
            scheduledCount = 0
            print("🔔 [Notifications] Skipped (status: \(statusDescription))")
            return
        }

        // Read user preferences
        let dueSoonDays = UserDefaults.standard.object(forKey: PreferenceKey.notifyDueSoonDays) as? Int ?? 3
        let notifyOnDueDay = UserDefaults.standard.object(forKey: PreferenceKey.notifyOnDueDay) as? Bool ?? true
        let weeklySummary = UserDefaults.standard.object(forKey: PreferenceKey.weeklySummary) as? Bool ?? false

        // Fetch unpaid, non-deleted bills, soonest first
        let descriptor = FetchDescriptor<Bill>(
            predicate: #Predicate<Bill> { $0.isDeleted == false && $0.isPaid == false },
            sortBy: [SortDescriptor<Bill>(\.dueDate, order: .forward)]
        )
        let unpaidBills = (try? context.fetch(descriptor)) ?? []

        let now = Date()
        let calendar = Calendar.current
        var count = 0

        for bill in unpaidBills.prefix(Self.maxTrackedBills) {
            let due = calendar.startOfDay(for: bill.dueDate)

            // ── Due day ──
            if notifyOnDueDay {
                if let fireDate = calendar.date(
                    bySettingHour: Self.reminderHour,
                    minute: Self.reminderMinute,
                    second: 0,
                    of: due
                ), fireDate > now {
                    let ok = await addBillNotification(
                        identifier: "\(Self.dueDayPrefix)\(bill.id)",
                        bill: bill,
                        title: "\(bill.title) is due today",
                        body: dueDayBody(for: bill),
                        fireDate: fireDate
                    )
                    if ok { count += 1 }
                }
            }

            // ── Due soon ──
            if dueSoonDays > 0 {
                if let soonDay = calendar.date(byAdding: .day, value: -dueSoonDays, to: due),
                   let fireDate = calendar.date(
                    bySettingHour: Self.reminderHour,
                    minute: Self.reminderMinute,
                    second: 0,
                    of: soonDay
                   ), fireDate > now {
                    let dayWord = dueSoonDays == 1 ? "day" : "days"
                    let ok = await addBillNotification(
                        identifier: "\(Self.dueSoonPrefix)\(bill.id)",
                        bill: bill,
                        title: "\(bill.title) due in \(dueSoonDays) \(dayWord)",
                        body: dueSoonBody(for: bill),
                        fireDate: fireDate
                    )
                    if ok { count += 1 }
                }
            }
        }

        // ── Weekly summary ──
        if weeklySummary {
            if await addWeeklySummary() { count += 1 }
        }

        scheduledCount = count
        print("🔔 [Notifications] Scheduled \(count) reminder(s) across \(unpaidBills.count) unpaid bill(s)")
    }

    // MARK: - Notification builders
    private func addBillNotification(
        identifier: String,
        bill: Bill,
        title: String,
        body: String,
        fireDate: Date
    ) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Self.categoryId
        content.userInfo = ["billId": bill.id]

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await center.add(request)
            return true
        } catch {
            print("❌ [Notifications] Failed to add \(identifier): \(error)")
            return false
        }
    }

    private func addWeeklySummary() async -> Bool {
        var comps = DateComponents()
        comps.weekday = 1 // Sunday in Gregorian calendar
        comps.hour = Self.reminderHour
        comps.minute = Self.reminderMinute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)

        let content = UNMutableNotificationContent()
        content.title = "Weekly summary"
        content.body = "Open RentaMan to review last week's spending and this week's bills."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: Self.weeklySummaryId,
            content: content,
            trigger: trigger
        )
        do {
            try await center.add(request)
            return true
        } catch {
            print("❌ [Notifications] Failed to add weekly summary: \(error)")
            return false
        }
    }

    // MARK: - Body text
    private func dueDayBody(for bill: Bill) -> String {
        let amount = CurrencyFormatter.format(bill.amount, as: .ksh)
        if let prop = bill.property {
            return "\(amount) · \(prop.name)"
        }
        return amount
    }

    private func dueSoonBody(for bill: Bill) -> String {
        let amount = CurrencyFormatter.format(bill.amount, as: .ksh)
        let due = bill.dueDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return "\(amount) · Due \(due)"
    }

    // MARK: - Cleanup
    func removeAllOurNotifications() async {
        let requests = await center.pendingNotificationRequests()
        let ids = requests.map(\.identifier).filter {
            $0.hasPrefix(Self.dueSoonPrefix) ||
            $0.hasPrefix(Self.dueDayPrefix) ||
            $0 == Self.weeklySummaryId
        }
        if !ids.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        scheduledCount = 0
    }
}