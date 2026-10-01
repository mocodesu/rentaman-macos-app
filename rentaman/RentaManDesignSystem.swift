import SwiftUI

// MARK: - Extended Design System
extension RMDesign {

    // MARK: Surfaces
    static var pageBackground: Color  { Color(NSColor.windowBackgroundColor) }
    static var cardBackground: Color  { Color(NSColor.controlBackgroundColor) }
    static var fieldBackground: Color { Color(NSColor.textBackgroundColor) }

    // MARK: Borders
    static var borderColor: Color  { Color.gray.opacity(0.14) }
    static var dividerColor: Color { Color.gray.opacity(0.10) }

    // MARK: Accent
    static var accent: Color     { .accentColor }
    static var accentSoft: Color { Color.accentColor.opacity(0.10) }

    // MARK: Semantics
    static let success: Color = .green
    static let warning: Color = .orange
    static let danger:  Color = .red

    // MARK: Shadows (kept for compat — used sparingly)
    static let cardShadow:  Color = .black.opacity(0.04)
    static let hoverShadow: Color = .black.opacity(0.08)
}

// MARK: - Section Header
struct RMSectionHeader: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?
    var trailing: AnyView? = nil

    init(icon: String, iconColor: Color, title: String, subtitle: String? = nil) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
    }

    init<T: View>(icon: String, iconColor: Color, title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> T) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.trailing = AnyView(trailing())
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 16, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if let trailing {
                trailing
            }
        }
    }
}

// MARK: - Page Header (top of each main view)
struct RMPageHeader: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(RMDesign.accent)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

// MARK: - Hero KPI Card (flat metric card)
//
// The `gradient` parameter is retained for source compatibility but is
// intentionally unused — the card derives all of its color from `iconAccent`.
struct HeroKPICard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let gradient: LinearGradient   // retained for API compat — unused
    let iconAccent: Color

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            // Left accent bar
            Rectangle()
                .fill(iconAccent)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Text(title.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(iconAccent)
                }

                Text(value)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 108)
        .background(isHovered ? Color.gray.opacity(0.04) : RMDesign.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: RMDesign.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: RMDesign.cardRadius)
                .stroke(RMDesign.borderColor, lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(RMDesign.ease) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Stat Pill
struct StatPill: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(RMDesign.fieldBackground)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(RMDesign.borderColor, lineWidth: 1)
        )
    }
}

// MARK: - Empty State
struct RMEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)

            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Content Card
struct RMContentCard<Content: View>: View {
    let title: String?
    let icon: String?
    let iconColor: Color
    let subtitle: String?
    @ViewBuilder let content: Content

    init(
        title: String? = nil,
        icon: String? = nil,
        iconColor: Color = .blue,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title, let icon {
                RMSectionHeader(
                    icon: icon,
                    iconColor: iconColor,
                    title: title,
                    subtitle: subtitle
                )
            }

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RMDesign.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: RMDesign.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: RMDesign.cardRadius)
                .stroke(RMDesign.borderColor, lineWidth: 1)
        )
    }
}