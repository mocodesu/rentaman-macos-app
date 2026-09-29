import SwiftUI

struct SettingsRootView: View {
    @State private var selectedTab: SettingsTab = .general
    
    enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case properties = "Properties"
        case notifications = "Notifications"
        case convex = "Sync"
        case data = "Data"
        case about = "About"
        
        var id: String { self.rawValue }
        
        var icon: String {
            switch self {
            case .general: return "gearshape.fill"
            case .properties: return "house.fill"
            case .notifications: return "bell.fill"
            case .convex: return "icloud.fill"
            case .data: return "externaldrive.fill"
            case .about: return "info.circle.fill"
            }
        }
    }
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Section {
                    ForEach(SettingsTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
            .navigationTitle("Settings")
        } detail: {
            Group {
                switch selectedTab {
                case .general:
                    GeneralSettingsView()
                case .properties:
                    PropertiesSettingsView()
                case .notifications:
                    NotificationsSettingsView()
                case .convex:
                    ConvexSettingsView()
                case .data:
                    DataSettingsView()
                case .about:
                    AboutSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 780, idealWidth: 820, minHeight: 560, idealHeight: 620)
    }
}

// MARK: - Reusable Settings Section
struct SettingsSection<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: Content
    
    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            
            content
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                )
        }
    }
}

// MARK: - Settings Row
struct SettingsRow<Trailing: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?
    @ViewBuilder let trailing: Trailing
    
    init(icon: String, iconColor: Color = .blue, title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(iconColor.gradient)
                .cornerRadius(7)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            trailing
        }
        .padding(.vertical, 4)
    }
}