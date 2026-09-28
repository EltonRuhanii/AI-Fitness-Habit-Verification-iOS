import SwiftUI

struct PasswordResetView: View {
    @Bindable var viewModel: AuthViewModel

    var body: some View {
        AuthFormScaffold(title: "Reset password", subtitle: "We'll email you a link to choose a new password.") {
            FormField(title: "Email", systemImage: "envelope", text: $viewModel.email, kind: .email)
                .accessibilityIdentifier("reset.email")

            if let error = viewModel.errorMessage {
                InlineMessage(text: error)
            }
            if let info = viewModel.infoMessage {
                InlineMessage(text: info, style: .success)
            }
        } footer: {
            Button("Send reset link") {
                Task { await viewModel.sendPasswordReset() }
            }
            .buttonStyle(.primary(isLoading: viewModel.isLoading))
            .disabled(viewModel.email.isEmpty || viewModel.isLoading)
            .accessibilityIdentifier("reset.submit")
        }
    }
}
