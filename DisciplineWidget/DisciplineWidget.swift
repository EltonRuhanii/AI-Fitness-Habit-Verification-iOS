import SwiftUI
import WidgetKit
import DisciplineCore

// Medium home-screen widget: the streak top right, today's first three unfinished main
// activities on the left. It renders the snapshot the app writes to the shared App Group.

struct DisciplineEntry: TimelineEntry {
    let date: Date
    let display: WidgetSnapshot.Display?
}

struct DisciplineProvider: TimelineProvider {
    private var calendar: Calendar { Calendar.disciplineCalendar(timeZone: .current) }

    func placeholder(in context: Context) -> DisciplineEntry {
        DisciplineEntry(date: Date(), display: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (DisciplineEntry) -> Void) {
        let entry = context.isPreview ? placeholder(in: context) : makeEntry(at: Date())
        completion(entry)
    }

    /// One entry now and one at midnight (the snapshot already carries tomorrow's activities).
    func getTimeline(in context: Context, completion: @escaping (Timeline<DisciplineEntry>) -> Void) {
        let now = Date()
        let midnight = calendar.startOfDay(for: now).addingTimeInterval(24 * 3600)
        let entries = [makeEntry(at: now), makeEntry(at: midnight.addingTimeInterval(1))]
        completion(Timeline(entries: entries, policy: .after(midnight.addingTimeInterval(24 * 3600))))
    }

    private func makeEntry(at date: Date) -> DisciplineEntry {
        guard let data = UserDefaults(suiteName: WidgetSnapshot.appGroup)?.data(forKey: WidgetSnapshot.storageKey),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return DisciplineEntry(date: date, display: nil)
        }
        let day = DayKey.today(calendar: calendar, now: date)
        return DisciplineEntry(date: date, display: snapshot.display(on: day, calendar: calendar))
    }

    static let sample = WidgetSnapshot.Display(
        streak: 24,
        items: [
            .init(name: "Guitar", symbolName: "graduationcap.fill", detail: "25/60 min"),
            .init(name: "Spanish", symbolName: "graduationcap.fill", detail: "0/60 min"),
            .init(name: "Workout", symbolName: "dumbbell.fill", detail: "Photo needed")
        ],
        remaining: 3, challengeDay: 46, challengeLength: 90
    )
}

private enum Palette {
    static let accent = Color(red: 1.0, green: 0.42, blue: 0.17)
    static let accentSecondary = Color(red: 1.0, green: 0.77, blue: 0.24)
    static let background = Color(red: 0.06, green: 0.06, blue: 0.08)
    static let secondaryText = Color.white.opacity(0.6)
    static let success = Color(red: 0.2, green: 0.83, blue: 0.6)
}

struct DisciplineWidgetView: View {
    let entry: DisciplineEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            activities
            Spacer(minLength: 0)
            streak
        }
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Palette.background, Color(red: 0.12, green: 0.07, blue: 0.05)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    @ViewBuilder
    private var activities: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundStyle(Palette.accent)
            if let display = entry.display, let remaining = display.remaining {
                if display.items.isEmpty {
                    Label(remaining == 0 ? "All done today" : "Nothing due", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.success)
                } else {
                    ForEach(display.items, id: \.name) { item in
                        row(item)
                    }
                    if remaining > display.items.count {
                        Text("+\(remaining - display.items.count) more")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Palette.secondaryText)
                    }
                }
            } else {
                Text("Open Discipline to see today's activities.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.secondaryText)
            }
        }
    }

    private func row(_ item: WidgetSnapshot.Item) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.symbolName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Palette.accent)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Palette.accent.opacity(0.18)))
            VStack(alignment: .leading, spacing: 0) {
                Text(item.name)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(item.detail)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
            }
        }
    }

    private var streak: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [Palette.accentSecondary, Palette.accent], startPoint: .top, endPoint: .bottom))
                Text("\(entry.display?.streak ?? 0)")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
            Text("DAY STREAK")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(Palette.secondaryText)
            Spacer(minLength: 0)
            if let day = entry.display?.challengeDay, let length = entry.display?.challengeLength {
                Text("Day \(day)/\(length)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        guard let remaining = entry.display?.remaining, remaining > 0 else { return "TODAY" }
        return "TODAY · \(remaining) LEFT"
    }
}

struct DisciplineWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DisciplineWidget", provider: DisciplineProvider()) { entry in
            DisciplineWidgetView(entry: entry)
        }
        .configurationDisplayName("Today's discipline")
        .description("Your streak and the main activities you still have to finish today.")
        .supportedFamilies([.systemMedium])
    }
}

@main
struct DisciplineWidgetBundle: WidgetBundle {
    var body: some Widget {
        DisciplineWidget()
    }
}

#Preview(as: .systemMedium) {
    DisciplineWidget()
} timeline: {
    DisciplineEntry(date: .now, display: DisciplineProvider.sample)
    DisciplineEntry(date: .now, display: nil)
}
