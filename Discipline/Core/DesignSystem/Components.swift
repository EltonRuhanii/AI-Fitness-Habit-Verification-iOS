import SwiftUI

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var isLoading = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            configuration.label
                .opacity(isLoading ? 0 : 1)
            if isLoading {
                ProgressView().tint(.white)
            }
        }
        .font(Theme.Typography.headline)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(Theme.Palette.emberGradient.opacity(isEnabled ? 1 : 0.4))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .scaleEffect(configuration.isPressed ? 0.97 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.Palette.textPrimary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.headline)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Theme.Palette.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
    static func primary(isLoading: Bool) -> PrimaryButtonStyle { PrimaryButtonStyle(isLoading: isLoading) }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
    static func secondary(tint: Color) -> SecondaryButtonStyle { SecondaryButtonStyle(tint: tint) }
}

// MARK: - Cards

struct CardModifier: ViewModifier {
    var padding: CGFloat = Theme.Spacing.md

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
            )
    }
}

extension View {
    func card(padding: CGFloat = Theme.Spacing.md) -> some View {
        modifier(CardModifier(padding: padding))
    }

    /// Full-screen themed background used by every top-level screen.
    func screenBackground() -> some View {
        background(Theme.Palette.background.ignoresSafeArea())
    }
}

/// Uppercase section label, e.g. "TODAY".
struct SectionEyebrow: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(Theme.Typography.eyebrow)
                .tracking(1.2)
                .foregroundStyle(Theme.Palette.textSecondary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Form fields

struct FormField: View {
    enum Kind { case text, email, password, newPassword, name }

    let title: String
    let systemImage: String
    @Binding var text: String
    var kind: Kind = .text
    var identifier: String?

    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: systemImage)
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(width: 20)
                .accessibilityHidden(true)

            Group {
                if isSecure && !isRevealed {
                    SecureField(title, text: $text)
                } else {
                    TextField(title, text: $text)
                }
            }
            .font(Theme.Typography.body)
            .textContentType(AppConfiguration.current.isUITesting ? nil : contentType)
            .accessibilityIdentifier(identifier ?? title)
            .keyboardType(kind == .email ? .emailAddress : .default)
            .textInputAutocapitalization(kind == .name ? .words : .never)
            .autocorrectionDisabled(kind != .name)

            if isSecure {
                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
                .accessibilityLabel(isRevealed ? "Hide password" : "Show password")
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(minHeight: 54)
        .background(Theme.Palette.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }

    private var isSecure: Bool { kind == .password || kind == .newPassword }

    private var contentType: UITextContentType? {
        switch kind {
        case .email: return .username
        case .password: return .password
        case .newPassword: return .newPassword
        case .name: return .name
        case .text: return nil
        }
    }
}

// MARK: - Feedback

struct InlineMessage: View {
    enum Style { case error, info, success }

    let text: String
    var style: Style = .error

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xs) {
            Image(systemName: icon)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(Theme.Typography.callout)
        .foregroundStyle(color)
        .padding(Theme.Spacing.sm)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch style {
        case .error: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        }
    }

    private var color: Color {
        switch style {
        case .error: return Theme.Palette.danger
        case .info: return Theme.Palette.info
        case .success: return Theme.Palette.success
        }
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Theme.Palette.emberGradient)
                .padding(Theme.Spacing.lg)
                .background(Circle().fill(Theme.Palette.accent.opacity(0.12)))
                .accessibilityHidden(true)
            Text(title)
                .font(Theme.Typography.title2)
                .foregroundStyle(Theme.Palette.textPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.primary)
                    .padding(.top, Theme.Spacing.xs)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity)
    }
}

/// App mark: flame in an ember-gradient rounded square.
struct AppMark: View {
    var size: CGFloat = 72

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Theme.Palette.emberGradient)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "flame.fill")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(.white)
            )
            .shadow(color: Theme.Palette.accent.opacity(0.45), radius: size * 0.3, y: size * 0.1)
            .accessibilityHidden(true)
    }
}
