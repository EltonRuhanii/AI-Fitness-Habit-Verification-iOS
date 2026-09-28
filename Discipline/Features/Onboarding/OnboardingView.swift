import SwiftUI

struct OnboardingView: View {
    @State private var index = 0
    @State private var showsRules = false

    private let pages = OnboardingContent.pages

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $index) {
                    ForEach(pages) { page in
                        OnboardingPageView(page: page)
                            .tag(page.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: index)

                controls
            }
            .screenBackground()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if index < pages.count - 1 {
                        Button("Skip intro") { index = pages.count - 1 }
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
            }
            .navigationDestination(isPresented: $showsRules) {
                RulesAcceptanceView()
            }
        }
    }

    private var controls: some View {
        VStack(spacing: Theme.Spacing.lg) {
            PageIndicator(count: pages.count, index: index)

            HStack(spacing: Theme.Spacing.sm) {
                if index > 0 {
                    Button {
                        index -= 1
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.secondary)
                    .frame(width: 64)
                    .accessibilityLabel("Previous")
                }

                Button(isLastPage ? "Review the rules" : "Continue") {
                    if isLastPage {
                        showsRules = true
                    } else {
                        index += 1
                    }
                }
                .buttonStyle(.primary)
                .accessibilityIdentifier("onboarding.next")
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.lg)
    }

    private var isLastPage: Bool { index == pages.count - 1 }
}

private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Image(systemName: page.systemImage)
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(Theme.Palette.emberGradient)
                    .frame(width: 112, height: 112)
                    .background(
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .fill(Theme.Palette.accent.opacity(0.12))
                    )
                    .padding(.top, Theme.Spacing.xxl)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text(page.eyebrow.uppercased())
                        .font(Theme.Typography.eyebrow)
                        .tracking(1.2)
                        .foregroundStyle(Theme.Palette.accent)
                    Text(page.title)
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(page.body)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !page.points.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        ForEach(page.points, id: \.self) { point in
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.Palette.success)
                                    .accessibilityHidden(true)
                                Text(point)
                                    .font(Theme.Typography.callout)
                                    .foregroundStyle(Theme.Palette.textPrimary)
                            }
                        }
                    }
                    .card()
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.lg)
        }
    }
}

private struct PageIndicator: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? Theme.Palette.accent : Theme.Palette.textTertiary.opacity(0.4))
                    .frame(width: i == index ? 22 : 7, height: 7)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: index)
        .accessibilityElement()
        .accessibilityLabel("Page \(index + 1) of \(count)")
    }
}

#Preview {
    OnboardingView()
        .environment(SessionStore(auth: AppContainer.preview.auth, users: AppContainer.preview.users))
        .preferredColorScheme(.dark)
}
