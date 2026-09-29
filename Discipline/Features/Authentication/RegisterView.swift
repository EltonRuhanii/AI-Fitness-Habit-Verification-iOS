import SwiftUI
import DisciplineCore

struct RegisterView: View {
    @Bindable var viewModel: AuthViewModel

    var body: some View {
        AuthFormScaffold(title: "Create your account", subtitle: "Your commitments, your rules.") {
            FormField(title: "Name", systemImage: "person", text: $viewModel.displayName, kind: .name, identifier: "register.name")
            FormField(title: "Email", systemImage: "envelope", text: $viewModel.email, kind: .email, identifier: "register.email")
            FormField(title: "Password", systemImage: "lock", text: $viewModel.password, kind: .newPassword, identifier: "register.password")
            FormField(title: "Confirm password", systemImage: "lock.rotation", text: $viewModel.confirmPassword, kind: .newPassword, identifier: "register.confirmPassword")

            Text("At least \(CredentialValidator.minimumPasswordLength) characters, including a letter and a number.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textTertiary)

            if let error = viewModel.errorMessage {
                InlineMessage(text: error)
            }
        } footer: {
            Button("Create account") {
                Task { await viewModel.register() }
            }
            .buttonStyle(.primary(isLoading: viewModel.isLoading))
            .disabled(!viewModel.canRegister)
            .accessibilityIdentifier("register.submit")
        }
    }
}
