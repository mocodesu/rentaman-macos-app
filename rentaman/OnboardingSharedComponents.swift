import SwiftUI

// MARK: - Design System
enum RMDesign {
    // Corner radii
    static let cardRadius: CGFloat = 20
    static let buttonRadius: CGFloat = 12
    static let fieldRadius: CGFloat = 10
    
    // Spacing
    static let outerPadding: CGFloat = 40
    static let cardPadding: CGFloat = 28
    
    // Animation
    static let springFast = Animation.spring(response: 0.4, dampingFraction: 0.75)
    static let springSmooth = Animation.spring(response: 0.55, dampingFraction: 0.82)
    
    // Gradient
    static let accentGradient = LinearGradient(
        colors: [Color.blue, Color.purple.opacity(0.85)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Progress Steps
struct ProgressStepsView: View {
    let current: Int
    let total: Int
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? Color.blue : Color.gray.opacity(0.2))
                    .frame(height: 4)
                    .frame(maxWidth: index == current ? 32 : 16)
                    .animation(RMDesign.springSmooth, value: current)
            }
        }
    }
}

// MARK: - Primary Button
struct OnboardingButton: View {
    let title: String
    let systemImage: String?
    var style: ButtonStyle = .primary
    let action: () -> Void
    
    enum ButtonStyle {
        case primary
        case secondary
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon = systemImage {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .foregroundStyle(style == .primary ? .white : .primary)
            .background {
                if style == .primary {
                    RoundedRectangle(cornerRadius: RMDesign.buttonRadius)
                        .fill(RMDesign.accentGradient)
                } else {
                    RoundedRectangle(cornerRadius: RMDesign.buttonRadius)
                        .fill(Color.gray.opacity(0.12))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step Header
struct StepHeader: View {
    let title: String
    let subtitle: String
    
    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            Text(title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
            
            Text(subtitle)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
    }
}