import SwiftUI

// MARK: - Step 1: Welcome
struct OnboardingWelcomeStep: View {
    let onNext: () -> Void
    
    @State private var iconScale: CGFloat = 0.6
    @State private var iconOpacity: Double = 0
    @State private var titleOpacity: Double = 0
    @State private var subtitleOpacity: Double = 0
    @State private var buttonOpacity: Double = 0
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Animated hero icon
            ZStack {
                Circle()
                    .fill(RMDesign.accentGradient)
                    .frame(width: 140, height: 140)
                    .blur(radius: 20)
                    .opacity(0.4)
                
                Image(systemName: "house.lodge.fill")
                    .font(.system(size: 78, weight: .light))
                    .foregroundStyle(RMDesign.accentGradient)
                    .symbolRenderingMode(.hierarchical)
            }
            .scaleEffect(iconScale)
            .opacity(iconOpacity)
            
            Spacer().frame(height: 40)
            
            VStack(spacing: 12) {
                Text("Welcome to RentaMan")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .opacity(titleOpacity)
                
                Text("Manage every bill, every house, in one place. Let's get you set up in under a minute.")
                    .font(.system(size: 15))
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
            withAnimation(.spring(response: 0.7, dampingFraction: 0.65).delay(0.05)) {
                iconScale = 1.0
                iconOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.25)) {
                titleOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.4)) {
                subtitleOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.55)) {
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
            
            Spacer().frame(height: 40)
            
            HStack(spacing: 20) {
                CurrencyCard(currency: .ksh, isSelected: selected == .ksh) {
                    withAnimation(RMDesign.springFast) { selected = .ksh }
                }
                CurrencyCard(currency: .usd, isSelected: selected == .usd) {
                    withAnimation(RMDesign.springFast) { selected = .usd }
                }
            }
            .frame(maxWidth: 540)
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
            VStack(spacing: 14) {
                Text(currency.symbol)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .frame(height: 52)
                
                Text(currency.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? .white.opacity(0.95) : .primary)
                
                Text(currency.rawValue)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: RMDesign.cardRadius)
                        .fill(RMDesign.accentGradient)
                        .shadow(color: Color.blue.opacity(0.35), radius: 16, x: 0, y: 8)
                } else {
                    RoundedRectangle(cornerRadius: RMDesign.cardRadius)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: RMDesign.cardRadius)
                                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                        )
                }
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                        .padding(14)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.0 : 0.97)
        .animation(RMDesign.springFast, value: isSelected)
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
            
            Spacer().frame(height: 32)
            
            VStack(spacing: 20) {
                // Name field
                VStack(alignment: .leading, spacing: 8) {
                    Label("Property Name", systemImage: "textformat")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    
                    TextField("e.g., Main House, Kilimani Apartment", text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(RMDesign.fieldRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: RMDesign.fieldRadius)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                }
                
                // Budget field
                VStack(alignment: .leading, spacing: 8) {
                    Label("Monthly Budget (optional)", systemImage: "banknote")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        Text(currency.symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.secondary)
                        
                        TextField("0.00", text: $budget)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                            .onChange(of: budget) { _, newValue in
                                let filtered = newValue.filter { "0123456789.".contains($0) }
                                if filtered != newValue { budget = filtered }
                            }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(RMDesign.fieldRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: RMDesign.fieldRadius)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                }
                
                // Color picker
                VStack(alignment: .leading, spacing: 10) {
                    Label("Color Tag", systemImage: "paintpalette")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 12) {
                        ForEach(colorOptions, id: \.self) { hex in
                            ColorChip(hex: hex, isSelected: colorHex == hex) {
                                withAnimation(RMDesign.springFast) { colorHex = hex }
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
                .frame(width: 32, height: 32)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .padding(2)
                        .opacity(isSelected ? 1 : 0)
                )
                .overlay(
                    Circle()
                        .stroke(Color(hex: hex).opacity(0.3), lineWidth: 3)
                        .scaleEffect(isSelected ? 1.35 : 1.0)
                        .opacity(isSelected ? 1 : 0)
                )
                .scaleEffect(isSelected ? 1.1 : 1.0)
                .animation(RMDesign.springFast, value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step 4: Finish
struct OnboardingFinishStep: View {
    let propertyName: String
    let currency: AppCurrency
    let onFinish: () -> Void
    
    @State private var checkScale: CGFloat = 0.4
    @State private var checkOpacity: Double = 0
    @State private var ringProgress: CGFloat = 0
    @State private var contentOpacity: Double = 0
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Animated success ring
            ZStack {
                Circle()
                    .stroke(Color.green.opacity(0.15), lineWidth: 6)
                    .frame(width: 120, height: 120)
                
                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(
                        LinearGradient(colors: [.green, .mint], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "checkmark")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [.green, .mint], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .scaleEffect(checkScale)
                    .opacity(checkOpacity)
            }
            
            Spacer().frame(height: 36)
            
            VStack(spacing: 12) {
                Text("You're all set!")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                
                VStack(spacing: 6) {
                    if propertyName.isEmpty {
                        Text("Add your first property from the sidebar to get started.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("**\(propertyName)** is ready to track.")
                            .foregroundStyle(.secondary)
                        
                        Text("Default currency: **\(currency.displayName)**")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.system(size: 15))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            }
            .opacity(contentOpacity)
            
            Spacer()
            
            OnboardingButton(title: "Enter RentaMan", systemImage: "arrow.right.circle.fill", action: onFinish)
                .frame(maxWidth: 280)
                .opacity(contentOpacity)
                .padding(.bottom, RMDesign.outerPadding)
        }
        .padding(.horizontal, RMDesign.outerPadding)
        .onAppear {
            withAnimation(.easeOut(duration: 0.7).delay(0.1)) {
                ringProgress = 1.0
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.6)) {
                checkScale = 1.0
                checkOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.85)) {
                contentOpacity = 1.0
            }
        }
    }
}