import SwiftUI

struct AboutSettingsView: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("About")
                        .font(.system(size: 22, weight: .semibold))
                    Text("Information about RentaMan.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                // Logo card
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(RMDesign.accentSoft)
                            .frame(width: 80, height: 80)

                        Image(systemName: "house.lodge.fill")
                            .font(.system(size: 38, weight: .light))
                            .foregroundStyle(RMDesign.accent)
                    }

                    VStack(spacing: 3) {
                        Text("RentaMan")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                        Text("Version \(appVersion) (\(buildNumber))")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Text("A professional bill and property manager for macOS, built with SwiftUI and SwiftData.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(RMDesign.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: RMDesign.cardRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: RMDesign.cardRadius)
                        .stroke(RMDesign.borderColor, lineWidth: 1)
                )

                // Credits
                SettingsSection(title: "Built With") {
                    VStack(spacing: 0) {
                        InfoRow(icon: "swift", color: .orange, title: "SwiftUI & SwiftData", subtitle: "Apple's modern UI and persistence frameworks")
                        Divider().padding(.leading, 36).padding(.vertical, 4)
                        InfoRow(icon: "cloud.fill", color: RMDesign.accent, title: "Convex", subtitle: "Real-time backend for cross-device sync")
                        Divider().padding(.leading, 36).padding(.vertical, 4)
                        InfoRow(icon: "chart.bar.fill", color: RMDesign.success, title: "Swift Charts", subtitle: "Native data visualization")
                    }
                }

                SettingsSection(title: "Support") {
                    VStack(spacing: 0) {
                        Button {
                            // Open documentation URL
                        } label: {
                            InfoRow(icon: "book.fill", color: .purple, title: "Documentation", subtitle: "Learn how to use RentaMan")
                        }
                        .buttonStyle(.plain)

                        Divider().padding(.leading, 36).padding(.vertical, 4)

                        Button {
                            // Open feedback URL
                        } label: {
                            InfoRow(icon: "envelope.fill", color: RMDesign.accent, title: "Send Feedback", subtitle: "Report bugs or suggest features")
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    Spacer()
                    Text("© 2025 RentaMan. All rights reserved.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.top, 8)
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

struct InfoRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}