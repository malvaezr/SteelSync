import Foundation
import UserNotifications
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Manages all local notifications for SteelSync across Mac, iPad, and iPhone.
///
/// Scheduling strategy: **morning batch**. A single daily trigger fires at the
/// user's preferred time (default 7 AM local). At that moment the service scans
/// the DataStore for 7 notification types and schedules one grouped summary
/// plus individual actionable notifications. Each notification carries a
/// `steelsync://` deep-link URL so tapping it jumps straight to the relevant
/// section.
///
/// Cap: iOS limits pending notifications to 64. The service prioritizes by
/// urgency (overdue > due-today > upcoming) and truncates the rest.
@MainActor
final class NotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    // MARK: - Preferences (persisted in UserDefaults)

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "notif_enabled") }
    }
    @Published var batchHour: Int {
        didSet { UserDefaults.standard.set(batchHour, forKey: "notif_batch_hour") }
    }
    @Published var batchMinute: Int {
        didSet { UserDefaults.standard.set(batchMinute, forKey: "notif_batch_minute") }
    }
    @Published var enableOverdueTasks: Bool {
        didSet { UserDefaults.standard.set(enableOverdueTasks, forKey: "notif_overdue_tasks") }
    }
    @Published var enableOverdueRFIs: Bool {
        didSet { UserDefaults.standard.set(enableOverdueRFIs, forKey: "notif_overdue_rfis") }
    }
    @Published var enableOverdueInvoices: Bool {
        didSet { UserDefaults.standard.set(enableOverdueInvoices, forKey: "notif_overdue_invoices") }
    }
    @Published var enableBidDueSoon: Bool {
        didSet { UserDefaults.standard.set(enableBidDueSoon, forKey: "notif_bid_due_soon") }
    }
    @Published var enableBidFollowUp: Bool {
        didSet { UserDefaults.standard.set(enableBidFollowUp, forKey: "notif_bid_followup") }
    }
    @Published var enableMilestoneApproaching: Bool {
        didSet { UserDefaults.standard.set(enableMilestoneApproaching, forKey: "notif_milestone") }
    }
    @Published var enablePaymentReceived: Bool {
        didSet { UserDefaults.standard.set(enablePaymentReceived, forKey: "notif_payment_received") }
    }

    /// True after the user has granted (or denied) notification permission.
    @Published var permissionStatus: UNAuthorizationStatus = .notDetermined

    private override init() {
        let d = UserDefaults.standard
        self.isEnabled = d.object(forKey: "notif_enabled") as? Bool ?? true
        self.batchHour = d.object(forKey: "notif_batch_hour") as? Int ?? 7
        self.batchMinute = d.object(forKey: "notif_batch_minute") as? Int ?? 0
        self.enableOverdueTasks = d.object(forKey: "notif_overdue_tasks") as? Bool ?? true
        self.enableOverdueRFIs = d.object(forKey: "notif_overdue_rfis") as? Bool ?? true
        self.enableOverdueInvoices = d.object(forKey: "notif_overdue_invoices") as? Bool ?? true
        self.enableBidDueSoon = d.object(forKey: "notif_bid_due_soon") as? Bool ?? true
        self.enableBidFollowUp = d.object(forKey: "notif_bid_followup") as? Bool ?? true
        self.enableMilestoneApproaching = d.object(forKey: "notif_milestone") as? Bool ?? true
        self.enablePaymentReceived = d.object(forKey: "notif_payment_received") as? Bool ?? true
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Permission

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { [weak self] granted, _ in
            Task { @MainActor in
                self?.refreshPermissionStatus()
            }
        }
    }

    func refreshPermissionStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor [weak self] in
                self?.permissionStatus = settings.authorizationStatus
            }
        }
    }

    // MARK: - Schedule Morning Batch

    /// Cancels all pending SteelSync notifications and reschedules based on
    /// the current DataStore state + user preferences. Call this:
    ///   - On app launch (after data loads)
    ///   - After any data change that could affect notifications
    ///   - When the user changes notification preferences
    func scheduleMorningBatch(from store: DataStore) {
        guard isEnabled, permissionStatus == .authorized else { return }

        let center = UNUserNotificationCenter.current()
        // Remove all previously scheduled SteelSync notifications
        center.removeAllPendingNotificationRequests()

        var requests: [UNNotificationRequest] = []
        let now = Date()
        let calendar = Calendar.current

        // Build the daily trigger for batch time (repeats daily)
        var batchComponents = DateComponents()
        batchComponents.hour = batchHour
        batchComponents.minute = batchMinute
        let batchTrigger = UNCalendarNotificationTrigger(dateMatching: batchComponents, repeats: true)

        // ── 1. Overdue Tasks ──
        if enableOverdueTasks {
            let overdue = store.overdueTodos
            if !overdue.isEmpty {
                let content = UNMutableNotificationContent()
                content.title = "📋 \(overdue.count) Overdue Task\(overdue.count == 1 ? "" : "s")"
                content.body = overdue.prefix(3).map { $0.title }.joined(separator: ", ")
                    + (overdue.count > 3 ? " and \(overdue.count - 3) more" : "")
                content.sound = .default
                content.userInfo = ["url": "steelsync://tasks?filter=Overdue"]
                content.categoryIdentifier = "OVERDUE_TASK"
                requests.append(UNNotificationRequest(
                    identifier: "steelsync.overdue_tasks",
                    content: content,
                    trigger: batchTrigger
                ))
            }
        }

        // ── 2. Overdue RFIs ──
        if enableOverdueRFIs {
            var overdueRFIs: [(RFI, String)] = []
            for project in store.projects {
                for rfi in store.rfis(for: project.id) where rfi.isOverdue {
                    overdueRFIs.append((rfi, project.title))
                }
            }
            if !overdueRFIs.isEmpty {
                let content = UNMutableNotificationContent()
                content.title = "❓ \(overdueRFIs.count) Overdue RFI\(overdueRFIs.count == 1 ? "" : "s")"
                content.body = overdueRFIs.prefix(3)
                    .map { "RFI #\($0.0.number) — \($0.1)" }
                    .joined(separator: ", ")
                content.sound = .default
                content.userInfo = ["url": "steelsync://rfis"]
                requests.append(UNNotificationRequest(
                    identifier: "steelsync.overdue_rfis",
                    content: content,
                    trigger: batchTrigger
                ))
            }
        }

        // ── 3. Overdue Invoices ──
        if enableOverdueInvoices {
            let overdue = store.allInvoices.filter { $0.invoice.isOverdue }
            if !overdue.isEmpty {
                let total = overdue.reduce(Decimal(0)) { $0 + store.balanceRemaining(for: $1.invoice) }
                let content = UNMutableNotificationContent()
                content.title = "💰 \(overdue.count) Overdue Invoice\(overdue.count == 1 ? "" : "s")"
                content.body = "\(total.currencyFormatted) outstanding past due date"
                content.sound = .default
                content.userInfo = ["url": "steelsync://invoices?filter=overdue"]
                requests.append(UNNotificationRequest(
                    identifier: "steelsync.overdue_invoices",
                    content: content,
                    trigger: batchTrigger
                ))
            }
        }

        // ── 4. Bids Due Within 24h ──
        if enableBidDueSoon {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            let dueSoon = store.bids.filter {
                ($0.status == .pending || $0.status == .readyToSubmit)
                    && $0.bidDueDate >= now
                    && $0.bidDueDate <= tomorrow
            }
            for bid in dueSoon.prefix(5) {
                let content = UNMutableNotificationContent()
                content.title = "⏰ Bid Due Today"
                content.body = "\(bid.projectName) for \(bid.clientName) — \(bid.bidAmount.currencyFormatted)"
                content.sound = .default
                content.userInfo = ["url": "steelsync://projects"]
                content.categoryIdentifier = "BID_DUE"
                requests.append(UNNotificationRequest(
                    identifier: "steelsync.bid_due.\(bid.id.recordName)",
                    content: content,
                    trigger: batchTrigger
                ))
            }
        }

        // ── 5. Bid Follow-Up Reminders ──
        if enableBidFollowUp {
            let followUps = store.activeTodos.filter {
                $0.category == .bidFollowUp
                    && $0.dueDate != nil
                    && calendar.isDateInToday($0.dueDate!)
            }
            for todo in followUps.prefix(5) {
                let content = UNMutableNotificationContent()
                content.title = "📞 Follow Up on Bid"
                content.body = todo.title + (todo.notes.isEmpty ? "" : " — \(todo.notes)")
                content.sound = .default
                content.userInfo = ["url": "steelsync://tasks"]
                requests.append(UNNotificationRequest(
                    identifier: "steelsync.followup.\(todo.id.uuidString)",
                    content: content,
                    trigger: batchTrigger
                ))
            }
        }

        // ── 6. Schedule Milestones Starting Within 24h ──
        if enableMilestoneApproaching {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            let upcoming = store.ganttTasks.filter {
                $0.status != .completed
                    && $0.startDate >= now
                    && $0.startDate <= tomorrow
            }
            for task in upcoming.prefix(5) {
                let projectName = store.projects.first { $0.id.recordName == task.projectID }?.title ?? ""
                let content = UNMutableNotificationContent()
                content.title = task.status == .milestone ? "◆ Milestone Tomorrow" : "📅 Task Starting Tomorrow"
                content.body = "\(task.name) — \(projectName), \(task.durationDays)d task"
                content.sound = .default
                content.userInfo = ["url": "steelsync://today"]
                requests.append(UNNotificationRequest(
                    identifier: "steelsync.milestone.\(task.id.uuidString)",
                    content: content,
                    trigger: batchTrigger
                ))
            }
        }

        // ── 7. Payments Received (yesterday) ──
        if enablePaymentReceived {
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
            var recentPayments: [(Payment, String)] = []
            for project in store.projects {
                for payment in store.payments(for: project.id) {
                    if calendar.isDate(payment.date, inSameDayAs: yesterday)
                        || calendar.isDate(payment.date, inSameDayAs: now) {
                        recentPayments.append((payment, project.title))
                    }
                }
            }
            if !recentPayments.isEmpty {
                let total = recentPayments.reduce(Decimal(0)) { $0 + $1.0.amount }
                let content = UNMutableNotificationContent()
                content.title = "✅ Payment\(recentPayments.count == 1 ? "" : "s") Received"
                content.body = "\(total.currencyFormatted) from \(recentPayments.count) payment\(recentPayments.count == 1 ? "" : "s")"
                content.sound = .default
                content.userInfo = ["url": "steelsync://invoices"]
                requests.append(UNNotificationRequest(
                    identifier: "steelsync.payments_received",
                    content: content,
                    trigger: batchTrigger
                ))
            }
        }

        // ── Morning summary notification ──
        let totalItems = requests.count
        if totalItems > 0 {
            let summary = UNMutableNotificationContent()
            summary.title = "SteelSync Morning Briefing"
            summary.body = "\(totalItems) item\(totalItems == 1 ? "" : "s") need\(totalItems == 1 ? "s" : "") your attention today."
            summary.sound = .default
            summary.userInfo = ["url": "steelsync://today"]
            summary.threadIdentifier = "steelsync.morning"
            // Fire 1 minute before the batch so the summary shows first
            var earlyComponents = batchComponents
            earlyComponents.minute = max(0, (earlyComponents.minute ?? 0) - 1)
            let earlyTrigger = UNCalendarNotificationTrigger(dateMatching: earlyComponents, repeats: true)
            requests.insert(UNNotificationRequest(
                identifier: "steelsync.morning_summary",
                content: summary,
                trigger: earlyTrigger
            ), at: 0)
        }

        // ── Enforce 64-notification cap ──
        let capped = Array(requests.prefix(60))  // Leave 4 slots for system

        for request in capped {
            center.add(request) { error in
                if let error {
                    print("[Notifications] Failed to schedule \(request.identifier): \(error)")
                }
            }
        }

        print("[Notifications] Scheduled \(capped.count) notifications for \(batchHour):\(String(format: "%02d", batchMinute)) daily batch")
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Handle notification tap — extract the URL and post it to the app.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let urlString = userInfo["url"] as? String,
           let url = URL(string: urlString) {
            Task { @MainActor in
                #if os(macOS)
                NSWorkspace.shared.open(url)
                #else
                await UIApplication.shared.open(url)
                #endif
            }
        }
        completionHandler()
    }

    /// Show notifications even when the app is in foreground (banner on Mac/iPad).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}
