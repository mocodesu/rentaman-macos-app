import SwiftUI
import SwiftData

// MARK: - SyncState Helpers (fix for == .error)
extension SyncState {
    var isError: Bool {
        if case .error = self { return true }
        return false
    }
    var isLive: Bool {
        if case .live = self { return true }
        return false
    }
    var isSyncing: Bool {
        if case .syncing = self { return true }
        return false
    }
    var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }
    var isLocalOnly: Bool {
        if case .localOnly = self { return true }
        return false
    }
}

// MARK: - Profile View
struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthService.self) private var auth
    @Environment(SyncService.self) private var syncService
    @Environment(\.appCurrency) private var currency: AppCurrency

    @Query private var properties: [Property]
    @Query(filter: #Predicate<Bill> { $0.isDeleted == false })
    private var allBills: [Bill]

    private var displayName: String {
        if case .signedIn(_, let name) = auth.state, let name = name, !name.isEmpty {
            return name
        }
        return "RentaMan User"
    }

    private var email: String {
        if case .signedIn(let email, _) = auth.state { return email }
        return "—"
    }

    private var initials: String {
        if case .signedIn(let email, let name) = auth.state {
            if let name = name, !name.isEmpty {
                return String(name.prefix(1)).uppercased()
            }
            return String(email.prefix(1)).uppercased()
        }
        return "?"
    }

    private var paidThisMonth: Double {
        let calendar = Calendar.current
        let now = Date()
        return allBills
            .filter {
                $0.isPaid &&
                calendar.component(.month, from: $0.dueDate) == calendar.component(.month, from: now) &&
                calendar.component(.year, from: $0.dueDate) == calendar.component(.year, from: now)
            }
            .reduce(0.0) { $0 + $1.amount }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // MARK: - Hero
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(RMDesign.accentSoft)
                            .frame(width: 80, height: 80)
                        Text(initials)
                            .font(.system(size: 32, weight: .semibold, design: .rounded))
                            .foregroundStyle(RMDesign.accent)
                    }

                    VStack(spacing: 3) {
                        Text(displayName)
                            .font(.system(size: 18, weight: .semibold))
                        Text(email)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 12)

                // MARK: - Stats
                HStack(spacing: 10) {
                    ProfileStatCard(icon: "house.fill", iconColor: RMDesign.accent, value: "\(properties.count)", label: "Properties")
                    ProfileStatCard(icon: "doc.text.fill", iconColor: .purple, value: "\(allBills.count)", label: "Total Bills")
                    ProfileStatCard(icon: "checkmark.circle.fill", iconColor: RMDesign.success, value: "\(allBills.filter { $0.isPaid }.count)", label: "Paid")
                    ProfileStatCard(icon: "banknote.fill", iconColor: RMDesign.warning, value: CurrencyFormatter.format(paidThisMonth, as: currency), label: "Paid this month")
                }
                .padding(.horizontal, 24)

                // MARK: - Account
                ProfileSection(title: "Account", icon: "person.crop.circle.fill", iconColor: RMDesign.accent) {
                    VStack(spacing: 0) {
                        ProfileRow(icon: "envelope.fill", label: "Email", value: email)
                        Divider().padding(.leading, 36).padding(.vertical, 4)
                        ProfileRow(icon: "person.fill", label: "Name", value: displayName)
                        Divider().padding(.leading, 36).padding(.vertical, 4)
                        ProfileRow(
                            icon: "key.fill",
                            label: "API Key",
                            value: auth.apiKey != nil ? "••••\(auth.apiKey!.suffix(6))" : "—"
                        )
                    }
                }
                .padding(.horizontal, 24)

                // MARK: - Sync Status
                ProfileSection(title: "Sync", icon: "icloud.fill", iconColor: RMDesign.success) {
                    VStack(spacing: 0) {
                        ProfileRow(
                            icon: syncService.state.icon,
                            label: "Status",
                            value: syncService.state.label,
                            valueColor: syncService.state.isError ? RMDesign.danger : RMDesign.success
                        )

                        if let last = syncService.lastSyncAt {
                            Divider().padding(.leading, 36).padding(.vertical, 4)
                            ProfileRow(
                                icon: "clock.fill",
                                label: "Last sync",
                                value: last.formatted(date: .abbreviated, time: .shortened)
                            )
                        }

                        Divider().padding(.leading, 36).padding(.vertical, 4)

                        HStack(spacing: 10) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(RMDesign.success)
                                .clipShape(RoundedRectangle(cornerRadius: 5))

                            Text("Force sync now")
                                .font(.system(size: 12.5, weight: .medium))

                            Spacer()

                            Button {
                                Task { await syncService.forceSync() }
                            } label: {
                                Text("Sync Now")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(.horizontal, 24)

                // MARK: - Sign Out
                Button {
                    auth.signOut()
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Sign Out").fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(RMDesign.danger)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(RMDesign.pageBackground)
    }
}

// MARK: - Profile Stat Card
private struct ProfileStatCard: View {
    let icon: String
    let iconColor: Color
    let value: String
    let label: String

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 30, height: 30)
                .background(iconColor.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(spacing: 1) {
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .monospacedDigit()
                Text(label)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(isHovered ? Color.gray.opacity(0.04) : RMDesign.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: RMDesign.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: RMDesign.cardRadius)
                .stroke(RMDesign.borderColor, lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(RMDesign.ease) { isHovered = hovering }
        }
    }
}

// MARK: - Profile Section
private struct ProfileSection<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }

            content
                .padding(14)
                .background(RMDesign.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: RMDesign.cardRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: RMDesign.cardRadius)
                        .stroke(RMDesign.borderColor, lineWidth: 1)
                )
        }
    }
}

// MARK: - Profile Row
private struct ProfileRow: View {
    let icon: String
    let label: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Text(label)
                .font(.system(size: 12.5, weight: .medium))

            Spacer()

            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 4)
    }
}