import SwiftUI
import DisciplineCore

/// Entry point: shows the active challenge, or lets the participant start one.
struct ChallengeHubView: View {
    @Environment(HabitsStore.self) private var store

    var body: some View {
        Group {
            if let challenge = store.activeChallenge ?? store.upcomingChallenge {
                ChallengeDetailView(challenge: challenge)
            } else {
                ChallengeGalleryView()
            }
        }
    }
}

struct ChallengeGalleryView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Choose a challenge")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text("A challenge sets how long you commit and the rules you'll hold yourself to. You review and accept the rules before it starts.")
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Palette.textSecondary)

                NavigationLink(value: ChallengeSetupView.Kind.discipline75) {
                    card(icon: "flame.fill", title: "75 Day Discipline",
                         text: ChallengeTemplates.discipline75Description, badge: "Template")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("challenge.template75")

                NavigationLink(value: ChallengeSetupView.Kind.custom) {
                    card(icon: "slider.horizontal.3", title: "Custom challenge",
                         text: "Pick your own duration, choose which of your habits count, and set the rules.", badge: nil)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("challenge.custom")
            }
            .padding(Theme.Spacing.md)
        }
        .screenBackground()
        .navigationTitle("Challenge")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: ChallengeSetupView.Kind.self) { kind in
            ChallengeSetupView(kind: kind)
        }
    }

    private func card(icon: String, title: String, text: String, badge: String?) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.Palette.emberGradient))
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                HStack {
                    Text(title).font(Theme.Typography.headline).foregroundStyle(Theme.Palette.textPrimary)
                    if let badge {
                        Text(badge.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.Palette.accent)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Theme.Palette.accent.opacity(0.15)))
                    }
                }
                Text(text)
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").foregroundStyle(Theme.Palette.textTertiary)
        }
        .card()
    }
}

struct ChallengeDetailView: View {
    let challenge: Challenge

    @Environment(HabitsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsAbandon = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                if let progress = store.challengeProgress, store.activeChallenge?.id == challenge.id {
                    statsGrid(progress)
                } else {
                    InlineMessage(text: "Starts \(challenge.startDate.startDate(calendar: store.calendar).formatted(date: .complete, time: .omitted)).", style: .info)
                }
                rulesCard
                habitsCard
                if let errorMessage { InlineMessage(text: errorMessage) }
                Button("Abandon challenge", role: .destructive) { confirmsAbandon = true }
                    .buttonStyle(.secondary(tint: Theme.Palette.danger))
            }
            .padding(Theme.Spacing.md)
        }
        .screenBackground()
        .navigationTitle("Challenge")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Abandon \(challenge.name)?", isPresented: $confirmsAbandon, titleVisibility: .visible) {
            Button("Abandon challenge", role: .destructive) { abandon() }
        } message: {
            Text("Its habits stop from today. Your history is kept and still counts as research data.")
        }
    }

    private var header: some View {
        let progress = store.challengeProgress
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(challenge.name.uppercased())
                .font(Theme.Typography.eyebrow)
                .tracking(1.2)
                .foregroundStyle(Theme.Palette.accent)
            if let progress, store.activeChallenge?.id == challenge.id {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Day \(progress.dayNumber)")
                        .font(Theme.Typography.hero)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text("of \(progress.durationDays)")
                        .font(Theme.Typography.title2)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                ProgressBar(fraction: progress.fractionElapsed, height: 10)
                Text("\(progress.daysRemaining) days left · ends \(challenge.endDate.startDate(calendar: store.calendar).formatted(date: .abbreviated, time: .omitted))")
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Palette.textSecondary)
            } else {
                Text(challenge.name)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.textPrimary)
            }
            if !challenge.description.isEmpty {
                Text(challenge.description)
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
    }

    private func statsGrid(_ progress: ChallengeProgress) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.sm) {
            stat("Successful days", "\(progress.successfulDays)")
            stat("Missed days", "\(progress.failedDays)")
            stat("Current streak", challenge.rules.streakEnabled ? "\(store.streak.current)" : "Off")
            stat("Adherence", progress.adherence.map { "\(Int(($0 * 100).rounded()))%" } ?? "–")
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            SectionEyebrow(title: title)
            Text(value)
                .font(Theme.Typography.title2.monospacedDigit())
                .foregroundStyle(Theme.Palette.textPrimary)
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private var rulesCard: some View {
        let rules = challenge.rules
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionEyebrow(title: "Rules", trailing: "Locked")
            ruleRow("Streak", rules.streakEnabled ? "On" : "Off")
            ruleRow("Every commitment required", rules.requireAllHabits ? "Yes" : "No")
            ruleRow("Skipping", rules.allowSkipping ? (rules.defaultSkipConsequence?.title ?? "Allowed") : "Not allowed")
            ruleRow("Missed day", rules.missedDayBehavior == .breakStreak ? "Breaks streak" : "Pauses streak")
            ruleRow("Uncertain AI result", rules.uncertainPolicy == .countsAsResolved ? "Counts" : "Resubmit")
            ruleRow("AI confidence threshold", "\(Int((rules.confidenceThreshold * 100).rounded()))%")
            if let accepted = challenge.rulesAcceptedAt {
                Text("Accepted \(accepted.formatted(date: .abbreviated, time: .shortened))")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
        .card()
    }

    private func ruleRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.Palette.textSecondary)
            Spacer()
            Label(value, systemImage: "lock.fill")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(Theme.Palette.textPrimary)
        }
        .font(Theme.Typography.callout)
    }

    private var habitsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionEyebrow(title: "Commitments")
            ForEach(store.habits(in: challenge)) { habit in
                HStack(spacing: Theme.Spacing.sm) {
                    HabitIcon(category: habit.category, size: 32)
                    Text(habit.name).font(Theme.Typography.callout.weight(.semibold))
                    Spacer()
                    Text(habit.targetDescription).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.textSecondary)
                }
            }
        }
        .card()
    }

    private func abandon() {
        do {
            try store.abandon(challenge)
            dismiss()
        } catch {
            errorMessage = AppError.from(error).localizedDescription
        }
    }
}

/// Dashboard banner for the challenge in progress.
struct ChallengeBanner: View {
    let challenge: Challenge
    let progress: ChallengeProgress?

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(challenge.name.uppercased())
                    .font(Theme.Typography.eyebrow)
                    .tracking(1.2)
                    .foregroundStyle(Theme.Palette.accent)
                if let progress {
                    Text("Day \(progress.dayNumber) of \(progress.durationDays)")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    ProgressBar(fraction: progress.fractionElapsed, height: 6)
                } else {
                    Text("Starts \(challenge.startDate.description)")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Palette.textPrimary)
                }
            }
            Image(systemName: "chevron.right").foregroundStyle(Theme.Palette.textTertiary)
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}
