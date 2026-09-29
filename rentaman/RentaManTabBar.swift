import SwiftUI

// MARK: - App Tabs
enum AppTab: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case bills = "Bills"
    case impact = "Impact"
    case reports = "Reports"
    case profile = "Profile"
    case settings = "Settings"

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

// MARK: - Native Bottom Tab Bar
struct RentaManTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases) { tab in
                NativeTabButton(
                    tab: tab,
                    isSelected: selection == tab
                ) {
                    guard selection != tab else { return }
                    withAnimation(.easeOut(duration: 0.18)) {
                        selection = tab
                    }
                }
            }
        }
        .padding(5)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.12), radius: 24, y: 8)
                .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
        }
    }
}

// MARK: - Native Tab Button
private struct NativeTabButton: View {
    let tab: AppTab
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                    .font(.system(size: 16, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .frame(height: 18)

                Text(tab.rawValue)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .frame(width: 80, height: 52)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.accentColor.opacity(0.2), lineWidth: 0.5)
                        )
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .help(tab.rawValue)
    }
}