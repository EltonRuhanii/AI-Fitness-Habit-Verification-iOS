import SwiftUI
import DisciplineCore

/// Aggregate, anonymous comparison of the two experimental conditions. Shows only counts and
/// rates per condition: no names, emails, photos or per-participant rows.
struct ResearchDashboardView: View {
    let service: ResearchService

    @State private var statistics: [TrackingCondition: ConditionStatistics] = [:]
    @State private var recordCount = 0
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var exportFiles: [URL] = []
    @State private var isExporting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                if !service.isStudyData {
                    InlineMessage(text: "Demo mode: this preview uses only your own local data. With the study backend, researchers see all consenting participants.", style: .info)
                }
                if let errorMessage {
                    InlineMessage(text: errorMessage)
                }
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    comparisonTable
                    exportCard
                    Text("Adherence = resolved due commitments ÷ due commitments. Day success excludes pending days. Verification rates use decided AI verifications only. Records are pseudonymous (participant IDs) and produced by \(DayResolver.version).")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            .padding(Theme.Spacing.md)
        }
        .screenBackground()
        .navigationTitle("Research")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Table

    private var comparisonTable: some View {
        let manual = statistics[.manual] ?? ConditionStatistics()
        let ai = statistics[.aiAssisted] ?? ConditionStatistics()
        return VStack(spacing: 0) {
            headerRow
            group("Sample")
            row("Participants", manual.participants, ai.participants)
            row("Successful days", manual.successfulDays, ai.successfulDays)
            row("Missed days", manual.failedDays, ai.failedDays)
            group("Adherence")
            row("Day success rate", percent(manual.daySuccessRate), percent(ai.daySuccessRate))
            row("Commitment adherence", percent(manual.adherence), percent(ai.adherence))
            row("Mean current streak", decimal(manual.meanCurrentStreak), decimal(ai.meanCurrentStreak))
            row("Mean longest streak", decimal(manual.meanLongestStreak), decimal(ai.meanLongestStreak))
            group("Completions")
            row("Self-reported", manual.selfReported, ai.selfReported)
            row("Verified", manual.verified, ai.verified)
            row("Rejected", manual.rejected, ai.rejected)
            row("Uncertain", manual.uncertain, ai.uncertain)
            group("AI verification")
            row("Verification rate", percent(manual.verificationRate), percent(ai.verificationRate))
            row("Rejection rate", percent(manual.rejectionRate), percent(ai.rejectionRate))
            row("Uncertain rate", percent(manual.uncertainRate), percent(ai.uncertainRate))
            row("Mean confidence", percent(manual.meanConfidence), percent(ai.meanConfidence))
            group("Accountability")
            row("Skips", manual.skipped, ai.skipped)
            row("Tasks completed", manual.accountabilityCompleted, ai.accountabilityCompleted)
            row("Tasks failed/expired", manual.accountabilityFailed, ai.accountabilityFailed)
            row("Completion rate", percent(manual.accountabilityCompletionRate), percent(ai.accountabilityCompletionRate), last: true)
        }
        .card(padding: 0)
    }

    private var headerRow: some View {
        HStack {
            Text("\(recordCount) participant-days")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
            Spacer()
            Text("Manual").frame(width: 80, alignment: .trailing)
            Text("AI-assisted").frame(width: 90, alignment: .trailing)
        }
        .font(Theme.Typography.caption.weight(.bold))
        .foregroundStyle(Theme.Palette.textSecondary)
        .padding(Theme.Spacing.md)
    }

    private func group(_ title: String) -> some View {
        SectionEyebrow(title: title)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, 4)
    }

    private func row(_ title: String, _ manual: Int, _ ai: Int, last: Bool = false) -> some View {
        row(title, "\(manual)", "\(ai)", last: last)
    }

    private func row(_ title: String, _ manual: String, _ ai: String, last: Bool = false) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.Palette.textPrimary)
            Spacer()
            Text(manual).frame(width: 80, alignment: .trailing)
            Text(ai).frame(width: 90, alignment: .trailing)
        }
        .font(Theme.Typography.callout.monospacedDigit())
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 6)
        .padding(.bottom, last ? Theme.Spacing.sm : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): manual \(manual), AI-assisted \(ai)")
    }

    private func percent(_ value: Double?) -> String {
        value.map { String(format: "%.1f%%", $0 * 100) } ?? "–"
    }

    private func decimal(_ value: Double?) -> String {
        value.map { String(format: "%.1f", $0) } ?? "–"
    }

    // MARK: Export

    private var exportCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionEyebrow(title: "Anonymous export")
            Text(service.isStudyData
                 ? "Daily records and completion events as CSV. Participant IDs are pseudonymous; no names, emails, habit names or photos are included."
                 : "Your local daily records as CSV (the same columns as the study export).")
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Palette.textSecondary)
            if exportFiles.isEmpty {
                Button {
                    Task { await export() }
                } label: {
                    Label("Prepare CSV export", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.primary(isLoading: isExporting))
                .disabled(isExporting)
                .accessibilityIdentifier("research.export")
            } else {
                ShareLink(items: exportFiles) {
                    Label("Share \(exportFiles.count) CSV file\(exportFiles.count == 1 ? "" : "s")", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.primary)
            }
        }
        .card()
    }

    // MARK: Actions

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let records = try await service.loadRecords()
            recordCount = records.count
            statistics = ResearchAggregator.summarize(records)
            errorMessage = nil
        } catch {
            errorMessage = AppError.from(error).localizedDescription
        }
    }

    private func export() async {
        isExporting = true
        defer { isExporting = false }
        do {
            let export = try await service.export()
            let stamp = Date().formatted(.iso8601.year().month().day())
            let directory = FileManager.default.temporaryDirectory
            var files: [URL] = []
            let daily = directory.appendingPathComponent("discipline-daily-records-\(stamp).csv")
            try export.dailyCSV.write(to: daily, atomically: true, encoding: .utf8)
            files.append(daily)
            if let events = export.eventsCSV {
                let url = directory.appendingPathComponent("discipline-events-\(stamp).csv")
                try events.write(to: url, atomically: true, encoding: .utf8)
                files.append(url)
            }
            exportFiles = files
        } catch {
            errorMessage = AppError.from(error).localizedDescription
        }
    }
}
