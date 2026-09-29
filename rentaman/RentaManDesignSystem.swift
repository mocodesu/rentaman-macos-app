import SwiftUI

// MARK: - Extended Design System
extension RMDesign {
    // New radii
    static let heroRadius: CGFloat = 20
    static let pillRadius: CGFloat = 100
    
    // Shadows
    static let cardShadow = Color.black.opacity(0.04)
    static let hoverShadow = Color.black.opacity(0.08)
    
    // Backgrounds
    static var cardBackground: Color { Color(NSColor.controlBackgroundColor) }
    static var pageBackground: Color { Color(NSColor.windowBackgroundColor) }
    static var fieldBackground: Color { Color(NSColor.textBackgroundColor) }
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
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(iconColor.gradient)
                .cornerRadius(9)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            if let trailing {
                trailing
            }
        }
    }
}

// MARK: - Page Header (for top of each main view)
struct RMPageHeader: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(RMDesign.accentGradient)
                    .frame(width: 48, height: 48)
                    .shadow(color: Color.blue.opacity(0.25), radius: 8, y: 4)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
    }
}

// MARK: - Hero KPI Card (gradient)
struct HeroKPICard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let gradient: LinearGradient
    let iconAccent: Color
    
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(9)
                
                Spacer()
                
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.75))
                    .tracking(0.5)
                
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 140)
        .background(
            ZStack {
                gradient
                
                // Subtle inner glow
                RadialGradient(
                    colors: [Color.white.opacity(0.15), Color.clear],
                    center: .topTrailing,
                    startRadius: 10,
                    endRadius: 150
                )
            }
        )
        .cornerRadius(RMDesign.heroRadius)
        .shadow(color: iconAccent.opacity(isHovered ? 0.35 : 0.2), radius: isHovered ? 16 : 10, y: 6)
        .scaleEffect(isHovered ? 1.015 : 1.0)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.2)) {
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
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 22, height: 22)
                .background(color.opacity(0.12))
                .cornerRadius(6)
            
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RMDesign.fieldBackground)
        .cornerRadius(RMDesign.pillRadius)
        .overlay(
            Capsule().stroke(Color.gray.opacity(0.12), lineWidth: 1)
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
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.08))
                    .frame(width: 72, height: 72)
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.blue)
            }
            
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
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
    
    init(title: String? = nil, icon: String? = nil, iconColor: Color = .blue, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.subtitle = subtitle
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RMDesign.cardBackground)
        .cornerRadius(RMDesign.cardRadius)
        .overlay(
            RoundedRectangle(cornerRadius: RMDesign.cardRadius)
                .stroke(Color.gray.opacity(0.08), lineWidth: 1)
        )
    }
}