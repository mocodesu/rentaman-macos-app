import SwiftUI

// MARK: - Step 1: Welcome
struct OnboardingWelcomeStep: View {
    let onNext: () -> Void

    @State private var iconScale: CGFloat = 0.85
    @State private var iconOpacity: Double = 0
    @State private var titleOpacity: Double = 0
    @State private var subtitleOpacity: Double = 0
    @State private var buttonOpacity: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Hero icon
            Image(systemName: "house.lodge.fill")
                .font(.system(size: 68, weight: .light))
                .foregroundStyle(RMDesign.accent)
                .symbolRenderingMode(.hierarchical)
                .scaleEffect(iconScale)
                .opacity(iconOpacity)

            Spacer().frame(height: 32)

            VStack(spacing: 10) {
                Text("Welcome to RentaMan")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .opacity(titleOpacity)

                Text("Manage every bill, every house, in one place. Let's get you set up in under a minute.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .opacity(subtitleOpacity)
            }

            Spacer()

            OnboardingButton(title: "Get Started", systemImage: "arrow.right", action: onNext)
                .frame(maxWidth: 260)
                .opacity(buttonOpacity)
                .padding(.bottom, RMDesign.outerPadding)
        }
        .padding(.horizontal, RMDesign.outerPadding)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.05)) {
                iconScale = 1.0
                iconOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.2)) {
                titleOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.35)) {
                subtitleOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.5)) {
                buttonOpacity = 1.0
            }
        }
    }
}

// MARK: - Step 2: Currency
struct OnboardingCurrencyStep: View {
    @Binding var selected: AppCurrency
    let onNext: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 20)

            StepHeader(
                title: "Choose your currency",
                subtitle: "Pick the default currency for displaying amounts. You can switch anytime."
            )

            Spacer().frame(height: 36)

            HStack(spacing: 16) {
                CurrencyCard(currency: .ksh, isSelected: selected == .ksh) {
                    withAnimation(RMDesign.ease) { selected = .ksh }
                }
                CurrencyCard(currency: .usd, isSelected: selected == .usd) {
                    withAnimation(RMDesign.ease) { selected = .usd }
                }
            }
            .frame(maxWidth: 500)
            .padding(.horizontal, RMDesign.outerPadding)

            Spacer()

            HStack(spacing: 12) {
                OnboardingButton(title: "Back", systemImage: "arrow.left", style: .secondary, action: onBack)
                    .frame(width: 120)

                OnboardingButton(title: "Continue", systemImage: "arrow.right", action: onNext)
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, RMDesign.outerPadding)
            .padding(.bottom, RMDesign.outerPadding)
        }
    }
}

struct CurrencyCard: View {
    let currency: AppCurrency
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                Text(currency.symbol)
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? RMDesign.accent : .primary)
                    .frame(height: 46)

                Text(currency.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(currency.rawValue)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 165)
            .background(isSelected ? RMDesign.accentSoft : RMDesign.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: RMDesign.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: RMDesign.cardRadius)
                    .stroke(isSelected ? RMDesign.accent : RMDesign.borderColor,
                            lineWidth: isSelected ? 2 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(RMDesign.accent)
                        .padding(12)
                }
            }
        }
        .buttonStyle(.plain)
        .animation(RMDesign.ease, value: isSelected)
    }
}

// MARK: - Step 3: First Property
struct OnboardingPropertyStep: View {
    @Binding var name: String
    @Binding var budget: String
    @Binding var colorHex: String
    let currency: AppCurrency
    let onNext: () -> Void
    let onBack: () -> Void

    private let colorOptions: [String] = [
        "#3B82F6", // Blue
        "#8B5CF6", // Purple
        "#EC4899", // Pink
        "#EF4444", // Red
        "#F59E0B", // Amber
        "#10B981", // Emerald
        "#14B8A6", // Teal
        "#6366F1"  // Indigo
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 20)

            StepHeader(
                title: "Add your first property",
                subtitle: "Start with one house. You can add more later from the sidebar."
            )

            Spacer().frame(height: 28)

            VStack(spacing: 18) {
                // Name field
                VStack(alignment: .leading, spacing: 6) {
                    Label("Property Name", systemImage: "textformat")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    TextField("e.g., Main House, Kilimani Apartment", text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(.horizontal, 12)
                        .frame(height: 40)
                        .background(RMDesign.fieldBackground)
                        .clipShape(RoundedRectangle(cornerRadius: RMDesign.fieldRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: RMDesign.fieldRadius)
                                .stroke(RMDesign.borderColor, lineWidth: 1)
                        )
                }

                // Budget field
                VStack(alignment: .leading, spacing: 6) {
                    Label("Monthly Budget (optional)", systemImage: "banknote")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    HStack {
                        Text(currency.symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)

                        TextField("0.00", text: $budget)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .onChange(of: budget) { _, newValue in
                                let filtered = newValue.filter { "0123456789.".contains($0) }
                                if filtered != newValue { budget = filtered }
                            }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(RMDesign.fieldBackground)
                    .clipShape(RoundedRectangle(cornerRadius: RMDesign.fieldRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: RMDesign.fieldRadius)
                            .stroke(RMDesign.borderColor, lineWidth: 1)
                    )
                }

                // Color picker
                VStack(alignment: .leading, spacing: 8) {
                    Label("Color Tag", systemImage: "paintpalette")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        ForEach(colorOptions, id: \.self) { hex in
                            ColorChip(hex: hex, isSelected: colorHex == hex) {
                                withAnimation(RMDesign.ease) { colorHex = hex }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 480)
            .padding(.horizontal, RMDesign.outerPadding)

            Spacer()

            HStack(spacing: 12) {
                OnboardingButton(title: "Back", systemImage: "arrow.left", style: .secondary, action: onBack)
                    .frame(width: 120)

                OnboardingButton(
                    title: name.isEmpty ? "Skip for now" : "Continue",
                    systemImage: "arrow.right",
                    action: onNext
                )
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, RMDesign.outerPadding)
            .padding(.bottom, RMDesign.outerPadding)
        }
    }
}

struct ColorChip: View {
    let hex: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 28, height: 28)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .padding(2)
                        .opacity(isSelected ? 1 : 0)
                )
                .overlay(
                    Circle()
                        .stroke(Color(hex: hex).opacity(0.3), lineWidth: 2.5)
                        .scaleEffect(isSelected ? 1.3 : 1.0)
                        .opacity(isSelected ? 1 : 0)
                )
                .scaleEffect(isSelected ? 1.08 : 1.0)
                .animation(RMDesign.ease, value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step 4: Finish
struct OnboardingFinishStep: View {
    let propertyName: String
    let currency: AppCurrency
    let onFinish: () -> Void

    @State private var checkScale: CGFloat = 0.5
    @State private var checkOpacity: Double = 0
    @State private var ringProgress: CGFloat = 0
    @State private var contentOpacity: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Success ring
            ZStack {
                Circle()
                    .stroke(RMDesign.success.opacity(0.15), lineWidth: 5)
                    .frame(width: 100, height: 100)

                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(RMDesign.success, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 100, height: 100)

                Image(systemName: "checkmark")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(RMDesign.success)
                    .scaleEffect(checkScale)
                    .opacity(checkOpacity)
            }

            Spacer().frame(height: 28)

            VStack(spacing: 10) {
                Text("You're all set!")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)

                VStack(spacing: 5) {
                    if propertyName.isEmpty {
                        Text("Add your first property from the sidebar to get started.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("**\(propertyName)** is ready to track.")
                            .foregroundStyle(.secondary)

                        Text("Default currency: **\(currency.displayName)**")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            }
            .opacity(contentOpacity)

            Spacer()

            OnboardingButton(title: "Enter RentaMan", systemImage: "arrow.right.circle.fill", action: onFinish)
                .frame(maxWidth: 260)
                .opacity(contentOpacity)
                .padding(.bottom, RMDesign.outerPadding)
        }
        .padding(.horizontal, RMDesign.outerPadding)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.1)) {
                ringProgress = 1.0
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.55)) {
                checkScale = 1.0
                checkOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.75)) {
                contentOpacity = 1.0
            }
        }
    }
}