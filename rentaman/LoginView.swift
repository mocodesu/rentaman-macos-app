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
            RMDesign.pageBackground
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // MARK: - Logo
                VStack(spacing: 10) {
                    Image(systemName: "house.lodge.fill")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(RMDesign.accent)
                        .symbolRenderingMode(.hierarchical)

                    Text("RentaMan")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))

                    Text("Manage every bill, every house.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                // MARK: - Card
                VStack(spacing: 0) {
                    // Mode toggle
                    HStack(spacing: 0) {
                        modeTab(title: "Sign In", tab: .signIn)
                        modeTab(title: "Sign Up", tab: .signUp)
                    }
                    .padding(3)
                    .background(Color.gray.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: RMDesign.cardRadius))
                    .padding([.horizontal, .top], 20)

                    // Fields
                    VStack(spacing: 12) {
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
                    .padding(20)

                    // Error
                    if let errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(errorMessage)
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(RMDesign.danger)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
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
                    .padding(20)
                }
                .frame(width: 400)
                .background(RMDesign.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: RMDesign.cardRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: RMDesign.cardRadius)
                        .stroke(RMDesign.borderColor, lineWidth: 1)
                )

                // Footer
                Text("Your data is stored locally and synced securely.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(40)
        }
        .frame(minWidth: 500, minHeight: 600)
    }

    // MARK: - Subviews
    private func modeTab(title: String, tab: Mode) -> some View {
        Button {
            withAnimation(RMDesign.ease) {
                mode = tab
                errorMessage = nil
            }
        } label: {
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(mode == tab ? RMDesign.cardBackground : Color.clear)
                .foregroundStyle(mode == tab ? .primary : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    mode == tab
                        ? RoundedRectangle(cornerRadius: 5).stroke(RMDesign.borderColor, lineWidth: 1)
                        : nil
                )
        }
        .buttonStyle(.plain)
    }

    private func field(icon: String, placeholder: String, text: Binding<String>, isSecure: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 18)

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
        .background(RMDesign.fieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: RMDesign.fieldRadius))
        .overlay(
            RoundedRectangle(cornerRadius: RMDesign.fieldRadius)
                .stroke(RMDesign.borderColor, lineWidth: 1)
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