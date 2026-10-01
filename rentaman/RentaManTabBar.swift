import SwiftUI

// MARK: - App Tabs
enum AppTab: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case bills     = "Bills"
    case impact    = "Impact"
    case reports   = "Reports"
    case profile   = "Profile"
    case settings  = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .bills:     return "list.bullet.rectangle.portrait"
        case .impact:    return "flame"
        case .reports:   return "chart.pie"
        case .profile:   return "person.crop.circle"
        case .settings:  return "gearshape"
        }
    }

    var selectedIcon: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .bills:     return "list.bullet.rectangle.portrait.fill"
        case .impact:    return "flame.fill"
        case .reports:   return "chart.pie.fill"
        case .profile:   return "person.crop.circle.fill"
        case .settings:  return "gearshape.fill"
        }
    }
}

// MARK: - App Navigation
@Observable
final class AppNavigation {
    static let shared = AppNavigation()
    var selectedTab: AppTab = .dashboard
    private init() {}
}

// MARK: - Sidebar
struct RentaManSidebar: View {
    @Binding var selection: AppTab
    @Environment(AuthService.self) private var auth

    private var subtitle: String {
        if case .signedIn(let email, _) = auth.state { return email }
        return "Not signed in"
    }

    private var mainTabs: [AppTab] { [.dashboard, .bills, .impact, .reports, .profile] }
    private var bottomTabs: [AppTab] { [.settings] }

    /// SwiftUI's `List(selection:)` wants an optional binding for single
    /// selection. We wrap our non-optional `AppTab` in one.
    private var listSelection: Binding<AppTab?> {
        Binding(
            get: { selection },
            set: { newValue in
                if let newValue { selection = newValue }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Traffic-light strip (also draggable)
            WindowDragHandle()
                .frame(height: 38)

            // Brand header
            HStack(spacing: 8) {
                Image(systemName: "house.lodge.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(RMDesign.accent)
                    .frame(width: 22, height: 22)
                    .background(RMDesign.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 5))

                VStack(alignment: .leading, spacing: 0) {
                    Text("RentaMan")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            // Navigation list
            List(selection: listSelection) {
                Section {
                    ForEach(mainTabs) { tab in
                        sidebarRow(tab)
                    }
                }

                Section {
                    ForEach(bottomTabs) { tab in
                        sidebarRow(tab)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .background(.regularMaterial)
    }

    // MARK: - Row
    @ViewBuilder
    private func sidebarRow(_ tab: AppTab) -> some View {
        Label {
            Text(tab.rawValue)
                .font(.system(size: 12.5, weight: selection == tab ? .medium : .regular))
        } icon: {
            Image(systemName: selection == tab ? tab.selectedIcon : tab.icon)
                .font(.system(size: 12.5))
                .foregroundStyle(selection == tab ? Color.accentColor : .secondary)
        }
        .tag(tab)
        .contentShape(Rectangle())
    }
}