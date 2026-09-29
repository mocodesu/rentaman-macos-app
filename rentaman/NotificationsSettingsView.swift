import SwiftUI

struct NotificationsSettingsView: View {
    @AppStorage(PreferenceKey.notifyDueSoonDays) private var dueSoonDays: Int = 3
    @AppStorage(PreferenceKey.notifyOnDueDay) private var notifyOnDueDay: Bool = true
    @AppStorage(PreferenceKey.weeklySummary) private var weeklySummary: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notifications")
                        .font(.system(size: 24, weight: .bold))
                    Text("Choose when RentaMan should remind you about bills.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                
                SettingsSection(title: "Reminders", subtitle: "All notifications are shown in the notification center.") {
                    VStack(spacing: 0) {
                        SettingsRow(
                            icon: "clock.badge.exclamationmark.fill",
                            iconColor: .orange,
                            title: "Remind me before due date",
                            subtitle: "Get notified \(dueSoonDays) day\(dueSoonDays == 1 ? "" : "s") before a bill is due."
                        ) {
                            Stepper("\(dueSoonDays) day\(dueSoonDays == 1 ? "" : "s")", value: $dueSoonDays, in: 1...14)
                                .frame(width: 130)
                        }
                        
                        Divider().padding(.leading, 40).padding(.vertical, 4)
                        
                        SettingsRow(
                            icon: "bell.badge.fill",
                            iconColor: .red,
                            title: "Notify on due day",
                            subtitle: "Show an alert on the day a bill is due."
                        ) {
                            Toggle("", isOn: $notifyOnDueDay)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                        
                        Divider().padding(.leading, 40).padding(.vertical, 4)
                        
                        SettingsRow(
                            icon: "envelope.badge.fill",
                            iconColor: .blue,
                            title: "Weekly summary",
                            subtitle: "Receive a digest every Sunday with last week's spending."
                        ) {
                            Toggle("", isOn: $weeklySummary)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                    }
                }
                
                // Info
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.system(size: 14))
                    Text("Notification scheduling will run in the background. If you deny the permission request, reminders will be shown as in-app banners instead.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.06))
                .cornerRadius(10)
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}