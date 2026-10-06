import SwiftUI
import DisciplineCore

/// Performance measurements recorded on this device, for the thesis performance analysis.
struct PerformanceView: View {
    @Environment(AppContainer.self) private var container
    @State private var exportURL: URL?
    @State private var confirmsClear = false

    var body: some View {
        let log = container.performance
        let summary = PerformanceSummary.summarize(log.samples)
        List {
            Section {
                ForEach(PerformanceMetric.allCases, id: \.self) { metric in
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text(metric.title).font(Theme.Typography.callout.weight(.semibold))
                        if let stats = summary[metric] {
                            Text("median \(format(stats.median)) · p95 \(format(stats.p95)) · mean \(format(stats.mean)) \(metric.unit)")
                                .font(Theme.Typography.caption.monospacedDigit())
                                .foregroundStyle(Theme.Palette.textSecondary)
                            Text("\(stats.count) sample\(stats.count == 1 ? "" : "s") · range \(format(stats.min))–\(format(stats.max)) \(metric.unit)")
                                .font(Theme.Typography.caption.monospacedDigit())
                                .foregroundStyle(Theme.Palette.textTertiary)
                        } else {
                            Text("No samples yet")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Palette.textTertiary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            } footer: {
                Text("Measured on this device: photo upload and AI verification round trips, and the camera analysis rate and Vision time per frame during push-up sessions. Nothing here is uploaded.")
            }

            Section {
                if let exportURL {
                    ShareLink(item: exportURL) { Label("Share CSV", systemImage: "square.and.arrow.up") }
                } else {
                    Button { prepareExport() } label: { Label("Prepare CSV", systemImage: "square.and.arrow.down") }
                        .disabled(log.samples.isEmpty)
                }
                Button("Clear measurements", role: .destructive) { confirmsClear = true }
                    .disabled(log.samples.isEmpty)
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Performance")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Clear all measurements?", isPresented: $confirmsClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) {
                log.clear()
                exportURL = nil
            }
        }
    }

    private func format(_ value: Double) -> String {
        value >= 100 ? String(Int(value.rounded())) : String(format: "%.1f", value)
    }

    private func prepareExport() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("discipline-performance-\(Date().formatted(.iso8601.year().month().day())).csv")
        do {
            try PerformanceSummary.csv(container.performance.samples).write(to: url, atomically: true, encoding: .utf8)
            exportURL = url
        } catch {
            exportURL = nil
        }
    }
}
