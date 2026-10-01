import SwiftUI

// MARK: - Design System
//
// Color policy:
//   .accent    → interactive elements, selection, focus
//   .success   → paid, on-track, restored
//   .warning   → due soon, over limit, paused
//   .danger    → overdue, over budget, delete, error
//   .primary / .secondary / .tertiary → everything else
//
// Forbidden: decorative gradients, multi-stop fills, colored card backgrounds.
// Category & payment-method colors are data — use them as small icon tints only.
//
enum RMDesign {

    // MARK: Corner Radii
    static let cardRadius: CGFloat   = 8
    static let buttonRadius: CGFloat = 6
    static let fieldRadius: CGFloat  = 6
    static let heroRadius: CGFloat   = 8
    static let pillRadius: CGFloat   = 999

    // MARK: Spacing (8pt grid)
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 20
    static let s6: CGFloat = 24

    static let outerPadding: CGFloat = 32
    static let cardPadding: CGFloat  = 16

    // MARK: Animation — subtle, no bounce
    static let springFast: Animation   = .easeOut(duration: 0.14)
    static let springSmooth: Animation = .easeOut(duration: 0.20)
    static let ease: Animation         = .easeOut(duration: 0.14)

    // MARK: Accent (compat alias — flat blue, no purple)
    // Kept for backward compatibility during the overhaul.
    // Prefer `RMDesign.accent` for new code. Will be removed in a later phase.
    static let accentGradient = LinearGradient(
        colors: [Color.accentColor, Color.accentColor],
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