import SwiftUI

struct LoginView: View {
    @Environment(AuthService.self) private var auth
    
    enum Mode { case signIn, signUp }
    @State private var mode: Mode = .signIn
    
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var name: String = ""
    
    @State private var errorMessage: String?
    @State private var isBusy: Bool = false
    
    private var isValid: Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedEmail.contains("@"), trimmedEmail.count >= 5 else { return false }
        guard password.count >= 8 else { return false }
        if mode == .signUp {
            guard password == confirmPassword else { return false }
        }
        return true
    }
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color(NSColor.windowBackgroundColor), Color(NSColor.controlBackgroundColor)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // MARK: - Logo
                VStack(spacing: 12) {
                    Image(systemName: "house.lodge.fill")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(.blue)
                        .symbolRenderingMode(.hierarchical)
                    
                    Text("RentaMan")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    
                    Text("Manage every bill, every house.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                // MARK: - Card
                VStack(spacing: 0) {
                    // Mode toggle
                    HStack(spacing: 0) {
                        modeTab(title: "Sign In", tab: .signIn)
                        modeTab(title: "Sign Up", tab: .signUp)
                    }
                    .padding(4)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                    .padding([.horizontal, .top], 24)
                    
                    // Fields
                    VStack(spacing: 14) {
                        if mode == .signUp {
                            field(
                                icon: "person.fill",
                                placeholder: "Name (optional)",
                                text: $name,
                                isSecure: false
                            )
                        }
                        
                        field(
                            icon: "envelope.fill",
                            placeholder: "Email",
                            text: $email,
                            isSecure: false
                        )
                        
                        field(
                            icon: "lock.fill",
                            placeholder: "Password (min 8 chars)",
                            text: $password,
                            isSecure: true
                        )
                        
                        if mode == .signUp {
                            field(
                                icon: "lock.rotation",
                                placeholder: "Confirm password",
                                text: $confirmPassword,
                                isSecure: true
                            )
                        }
                    }
                    .padding(24)
                    
                    // Error
                    if let errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(errorMessage)
                                .font(.caption)
                        }
                        .foregroundStyle(.red)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    // Action button
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            if isBusy {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
                            } else {
                                Image(systemName: mode == .signIn ? "arrow.right.circle.fill" : "person.badge.plus")
                            }
                            Text(mode == .signIn ? "Sign In" : "Create Account")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!isValid || isBusy)
                    .keyboardShortcut(.defaultAction)
                    .padding(24)
                }
                .frame(width: 420)
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.1), radius: 20, y: 8)
                
                // Footer
                Text("Your data is stored locally and synced securely.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(40)
        }
        .frame(minWidth: 500, minHeight: 600)
    }
    
    // MARK: - Subviews
    private func modeTab(title: String, tab: Mode) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                mode = tab
                errorMessage = nil
            }
        } label: {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(mode == tab ? Color.blue : Color.clear)
                .foregroundStyle(mode == tab ? .white : .primary)
                .cornerRadius(7)
        }
        .buttonStyle(.plain)
    }
    
    private func field(icon: String, placeholder: String, text: Binding<String>, isSecure: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            
            if isSecure {
                SecureField(placeholder, text: text)
                    .textFieldStyle(.plain)
            } else {
                TextField(placeholder, text: text)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textCase(.lowercase)
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Submit
    private func submit() async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }
        
        do {
            switch mode {
            case .signIn:
                try await auth.signIn(
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password
                )
            case .signUp:
                try await auth.signUp(
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password,
                    name: name.isEmpty ? nil : name
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}