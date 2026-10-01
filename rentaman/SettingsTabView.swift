import SwiftUI

struct SettingsTabView: View {
    @State private var selectedSection: SettingsSection = .general

    enum SettingsSection: String, CaseIterable, Identifiable {
        case general = "General"
        case properties = "Properties"
        case notifications = "Notifications"
        case sync = "Sync"
        case data = "Data"
        case about = "About"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general: return "gearshape.fill"
            case .properties: return "house.fill"
            case .notifications: return "bell.fill"
            case .sync: return "icloud.fill"
            case .data: return "externaldrive.fill"
            case .about: return "info.circle.fill"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsSectionPicker(selection: $selectedSection)
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 6)

            Divider().opacity(0.5)

            Group {
                switch selectedSection {
                case .general:       GeneralSettingsView()
                case .properties:    PropertiesSettingsView()
                case .notifications: NotificationsSettingsView()
                case .sync:          ConvexSettingsView()
                case .data:          DataSettingsView()
                case .about:         AboutSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(RMDesign.pageBackground)
    }
}

// MARK: - Section Picker
private struct SettingsSectionPicker: View {
    @Binding var selection: SettingsTabView.SettingsSection
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 3) {
            ForEach(SettingsTabView.SettingsSection.allCases) { section in
                Button {
                    withAnimation(RMDesign.ease) {
                        selection = section
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: section.icon)
                            .font(.system(size: 10, weight: .medium))
                        Text(section.rawValue)
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundStyle(selection == section ? .white : .primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background {
                        if selection == section {
                            Capsule()
                                .fill(RMDesign.accent)
                                .matchedGeometryEffect(id: "settingsTab", in: namespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background {
            Capsule()
                .fill(Color.gray.opacity(0.08))
                .overlay(Capsule().stroke(RMDesign.borderColor, lineWidth: 0.75))
        }
        .fixedSize()
    }
}