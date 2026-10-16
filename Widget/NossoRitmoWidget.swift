import SwiftUI
import WidgetKit

private enum WidgetConfig {
    static var groupID: String { Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String ?? "group.com.nyg007.nossoritmo" }
}
struct RhythmWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}
struct RhythmProvider: TimelineProvider {
    func placeholder(in context: Context) -> RhythmWidgetEntry { RhythmWidgetEntry(date: .now, snapshot: sample) }
    func getSnapshot(in context: Context, completion: @escaping (RhythmWidgetEntry) -> Void) {
        completion(RhythmWidgetEntry(date: .now, snapshot: context.isPreview ? sample : read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<RhythmWidgetEntry>) -> Void) {
        let now = Date(), snapshot = read()
        let nextRefresh = now.addingTimeInterval(3600)
        var dates = [now]
        dates += (snapshot?.events ?? []).map { $0.date.addingTimeInterval(1) }.filter { $0 > now && $0 < nextRefresh }
        if let boundary = snapshot?.weekEnd, boundary > now && boundary < nextRefresh { dates.append(boundary) }
        let entries = dates.sorted().map { RhythmWidgetEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(nextRefresh)))
    }
    private func read() -> WidgetSnapshot? {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetConfig.groupID)?.appendingPathComponent("snapshot.json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
    private var sample: WidgetSnapshot {
        WidgetSnapshot(generatedAt: .now, weekEnd: .now.addingTimeInterval(86400), theme: "pink", events: [
            WidgetEvent(id: "sample", title: "Um café sem pressa", date: .now.addingTimeInterval(3600), url: URL(string: "nossoritmo://agenda")!)
        ], goals: [WidgetGoal(id: "outdoors", title: "Ar livre · Casal", value: 1.5, target: 3), WidgetGoal(id: "streaming", title: "Streaming · Casal", value: 1, target: 2)])
    }
}
struct RhythmWidgetView: View {
    @Environment(\.widgetFamily) var family
    @Environment(\.colorScheme) var systemScheme
    var entry: RhythmWidgetEntry
    private var pink: Bool { entry.snapshot?.theme == "pink" }
    private var dark: Bool { entry.snapshot?.theme == "dark" }
    private var background: Color {
        if pink { return Color(red: 1, green: 0.93, blue: 0.95) }
        return dark ? Color(red: 0.13, green: 0.16, blue: 0.14) : Color(uiColor: .systemBackground)
    }
    var body: some View {
        let upcoming = entry.snapshot?.events.filter { $0.date >= entry.date } ?? []
        VStack(alignment: .leading, spacing: 10) {
            Label("Nosso Ritmo", systemImage: "heart.fill").font(.caption.bold()).foregroundStyle(pink ? Color.pink : Color.accentColor)
            if let event = upcoming.first {
                Link(destination: event.url) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(event.title).font(.headline).lineLimit(2)
                        Text(event.date, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(entry.snapshot == nil ? "Vamos começar?" : "Espaço para novos momentos").font(.headline)
                Text("Abra nosso calendário").font(.caption).foregroundStyle(.secondary)
            }
            if family == .systemMedium, let snapshot = entry.snapshot {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(snapshot.goals.prefix(2)) { goal in
                        let value = entry.date < snapshot.weekEnd ? goal.value : 0
                        Link(destination: URL(string: "nossoritmo://goals/\(goal.id)")!) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(goal.title).font(.caption2).lineLimit(1)
                                ProgressView(value: min(value, goal.target), total: max(0.001, goal.target))
                                Text("\(value.formatted(.number.precision(.fractionLength(0...1)))) / \(goal.target.formatted()) h").font(.caption2)
                            }
                        }
                    }
                }
                if upcoming.count > 1 { Text("Depois: \(upcoming[1].title)").font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(dark ? Color.white : Color.primary)
        .containerBackground(background, for: .widget)
        .environment(\.colorScheme, dark ? .dark : (["pink", "light"].contains(entry.snapshot?.theme ?? "") ? .light : systemScheme))
        .widgetURL(upcoming.first?.url ?? URL(string: "nossoritmo://agenda"))
        .accessibilityElement(children: .contain)
    }
}
@main struct NossoRitmoWidget: Widget {
    let kind = "NossoRitmoWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RhythmProvider()) { RhythmWidgetView(entry: $0) }
            .configurationDisplayName("Nosso Ritmo")
            .description("Nosso próximo encontro e as metas da semana.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
