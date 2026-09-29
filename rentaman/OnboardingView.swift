import SwiftUI
import SwiftData

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("displayCurrency") private var currencyRaw: String = AppCurrency.ksh.rawValue
    
    @Environment(\.modelContext) private var modelContext
    
    // Step state
    @State private var currentStep: Int = 0
    @State private var isForward: Bool = true
    private let totalSteps = 4
    
    // Collected data (carried across steps)
    @State private var selectedCurrency: AppCurrency = .ksh
    @State private var propertyName: String = ""
    @State private var propertyBudget: String = ""
    @State private var propertyColorHex: String = "#3B82F6"
    
    var body: some View {
        ZStack {
            // Animated gradient background
            RMDesign.accentGradient
                .ignoresSafeArea()
                .opacity(0.08)
            
            // Subtle radial glow
            RadialGradient(
                colors: [Color.blue.opacity(0.15), Color.clear],
                center: .topLeading,
                startRadius: 50,
                endRadius: 600
            )
            .ignoresSafeArea()
            .blur(radius: 40)
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    HStack(spacing: 10) {
                        Image(systemName: "house.lodge.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(RMDesign.accentGradient)
                        Text("RentaMan")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                    }
                    
                    Spacer()
                    
                    if currentStep < totalSteps - 1 {
                        Button("Skip") {
                            withAnimation(RMDesign.springSmooth) {
                                currentStep = totalSteps - 1
                                isForward = true
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, RMDesign.outerPadding)
                .padding(.top, 24)
                
                // Progress
                ProgressStepsView(current: currentStep, total: totalSteps)
                    .padding(.top, 20)
                    .padding(.horizontal, RMDesign.outerPadding)
                
                // Step Content
                ZStack {
                    stepContent
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(RMDesign.springSmooth, value: currentStep)
            }
        }
        .frame(minWidth: 720, minHeight: 620)
        .onAppear {
            selectedCurrency = AppCurrency(rawValue: currencyRaw) ?? .ksh
        }
    }
    
    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case 0:
            OnboardingWelcomeStep(onNext: goNext)
                .transition(stepTransition)
        case 1:
            OnboardingCurrencyStep(
                selected: $selectedCurrency,
                onNext: goNext,
                onBack: goBack
            )
            .transition(stepTransition)
        case 2:
            OnboardingPropertyStep(
                name: $propertyName,
                budget: $propertyBudget,
                colorHex: $propertyColorHex,
                currency: selectedCurrency,
                onNext: handlePropertyNext,
                onBack: goBack
            )
            .transition(stepTransition)
        case 3:
            OnboardingFinishStep(
                propertyName: propertyName,
                currency: selectedCurrency,
                onFinish: finishOnboarding
            )
            .transition(stepTransition)
        default:
            EmptyView()
        }
    }
    
    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: isForward ? .trailing : .leading)
                .combined(with: .opacity),
            removal: .move(edge: isForward ? .leading : .trailing)
                .combined(with: .opacity)
        )
    }
    
    // MARK: - Navigation
    private func goNext() {
        isForward = true
        withAnimation(RMDesign.springSmooth) {
            currentStep = min(currentStep + 1, totalSteps - 1)
        }
    }
    
    private func goBack() {
        isForward = false
        withAnimation(RMDesign.springSmooth) {
            currentStep = max(currentStep - 1, 0)
        }
    }
    
    private func handlePropertyNext() {
        let trimmedName = propertyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            goNext()
            return
        }
        
        let budgetInKsh: Double = {
            guard let entered = Double(propertyBudget) else { return 0 }
            return CurrencyFormatter.toKsh(entered, from: selectedCurrency)
        }()
        
        let property = Property(
            name: trimmedName,
            address: nil,
            colorHex: propertyColorHex,
            monthlyBudget: budgetInKsh,
            isDefault: true
        )
        
        modelContext.insert(property)
        try? modelContext.save()
        
        SyncService.shared.schedulePush()
        
        goNext()
    }
    
    private func finishOnboarding() {
        currencyRaw = selectedCurrency.rawValue
        
        withAnimation(RMDesign.springSmooth) {
            hasCompletedOnboarding = true
        }
    }
}
