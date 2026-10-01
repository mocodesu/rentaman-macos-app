import SwiftUI
import UserNotifications
import AppKit
import SwiftData

struct NotificationsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var service = NotificationService.shared

    @AppStorage(PreferenceKey.notifyDueSoonDays) private var dueSoonDays: Int = 3
    @AppStorage(PreferenceKey.notifyOnDueDay) private var notifyOnDueDay: Bool = true
    @AppStorage(PreferenceKey.weeklySummary) private var weeklySummary: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                permissionCard
                remindersSection
                if service.isEnabled && service.scheduledCount > 0 {
                    scheduledCard
                }
                infoFooter
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .task {
            await service.refreshAuthorizationStatus()
        }
        .onChange(of: dueSoonDays)   { _, _ in reschedule() }
        .onChange(of: notifyOnDueDay) { _, _ in reschedule() }
        .onChange(of: weeklySummary) { _, _ in reschedule() }
    }

    // MARK: - Header
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Notifications")
                .font(.system(size: 22, weight: .semibold))
            Text("Choose when RentaMan should remind you about bills.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Permission Card
    private var permissionCard: some View {
        HStack(spacing: 12) {
            Image(systemName: permissionIcon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(permissionColor)
                .frame(width: 34, height: 34)
                .background(permissionColor.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 1) {
                Text("Permission")
                    .font(.system(size: 12.5, weight: .semibold))
                Text(permissionMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            permissionAction
        }
        .padding(12)
        .background(permissionColor.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: RMDesign.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: RMDesign.cardRadius)
                .stroke(permissionColor.opacity(0.20), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var permissionAction: some View {
        switch service.authorizationStatus {
        case .notDetermined:
            Button {
                Task {
                    _ = await service.requestAuthorization()
                    await service.reschedule(context: modelContext)
                }
            } label: {
                Label("Enable", systemImage: "bell.badge.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

        case .denied:
            Button {
                openNotificationPreferences()
            } label: {
                Label("Open Settings", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

        default:
            Label("OK", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(RMDesign.success)
        }
    }

    private var permissionIcon: String {
        switch service.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return "bell.badge.fill"
        case .denied: return "bell.slash.fill"
        case .notDetermined: return "bell.fill"
        @unknown default: return "bell.fill"
        }
    }

    private var permissionColor: Color {
        switch service.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return RMDesign.success
        case .denied: return RMDesign.danger
        case .notDetermined: return RMDesign.warning
        @unknown default: return .secondary
        }
    }

    private var permissionMessage: String {
        switch service.authorizationStatus {
        case .authorized:
            return "Notifications are enabled. Reminders will fire even when RentaMan is closed."
        case .provisional:
            return "Provisional permission — reminders are delivered quietly."
        case .ephemeral:
            return "Temporary permission — reminders will stop soon."
        case .denied:
            return "Notifications are blocked in System Settings. Click Open Settings to allow them."
        case .notDetermined:
            return "RentaMan needs your permission to send bill reminders."
        @unknown default:
            return "Unknown authorization status."
        }
    }

    // MARK: - Reminders Section
    private var remindersSection: some View {
        SettingsSection(
            title: "Reminders",
            subtitle: service.isEnabled
                ? "All reminders are scheduled locally and appear in the notification center."
                : "Enable permission above to start receiving reminders."
        ) {
            VStack(spacing: 0) {
                SettingsRow(
                    icon: "clock.badge.exclamationmark.fill",
                    iconColor: RMDesign.warning,
                    title: "Remind me before due date",
                    subtitle: "Get notified \(dueSoonDays) day\(dueSoonDays == 1 ? "" : "s") before a bill is due, at 9:00 AM."
                ) {
                    Stepper("\(dueSoonDays) day\(dueSoonDays == 1 ? "" : "s")", value: $dueSoonDays, in: 1...14)
                        .frame(width: 130)
                        .disabled(!service.isEnabled)
                }

                Divider().padding(.leading, 36).padding(.vertical, 4)

                SettingsRow(
                    icon: "bell.badge.fill",
                    iconColor: RMDesign.danger,
                    title: "Notify on due day",
                    subtitle: "Alert at 9:00 AM on the day a bill is due."
                ) {
                    Toggle("", isOn: $notifyOnDueDay)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(!service.isEnabled)
                }

                Divider().padding(.leading, 36).padding(.vertical, 4)

                SettingsRow(
                    icon: "envelope.badge.fill",
                    iconColor: RMDesign.accent,
                    title: "Weekly summary",
                    subtitle: "A digest every Sunday at 9:00 AM with last week's spending."
                ) {
                    Toggle("", isOn: $weeklySummary)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(!service.isEnabled)
                }
            }
        }
        .opacity(service.isEnabled ? 1.0 : 0.7)
    }

    // MARK: - Scheduled Count Card
    private var scheduledCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(RMDesign.accent)
                .frame(width: 28, height: 28)
                .background(RMDesign.accent.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 1) {
                Text("\(service.scheduledCount) reminder\(service.scheduledCount == 1 ? "" : "s") scheduled")
                    .font(.system(size: 12.5, weight: .semibold))
                Text("Rebuilt automatically whenever bills change.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await service.reschedule(context: modelContext) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .background(RMDesign.accent.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: RMDesign.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: RMDesign.cardRadius)
                .stroke(RMDesign.accent.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Info Footer
    private var infoFooter: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(RMDesign.accent)
                .font(.system(size: 12))
            Text("Reminders are scheduled locally using the system notification center. If you deny permission, RentaMan will still function — you just won't receive alerts. Toggling any option above rebuilds the schedule automatically.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RMDesign.accent.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: RMDesign.cardRadius))
    }

    // MARK: - Helpers
    private func reschedule() {
        NotificationService.shared.scheduleReschedule(context: modelContext)
    }

    private func openNotificationPreferences() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.notifications"
        ]
        for raw in candidates {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}