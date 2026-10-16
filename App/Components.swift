import SwiftUI

struct RhythmSurface: ViewModifier {
    @AppStorage("theme") var theme = "system"
    func body(content: Content) -> some View {
        content.scrollContentBackground(.hidden)
            .background(theme == "pink" ? Color(red: 1, green: 0.94, blue: 0.96) : Color(uiColor: .systemGroupedBackground))
    }
}
extension View {
    func rhythmSurface() -> some View { modifier(RhythmSurface()) }
}

struct RhythmCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(.background, in: RoundedRectangle(cornerRadius: 24))
    }
}
struct EmptyHint: View {
    let title: String
    let message: String
    let symbol: String
    var body: some View { ContentUnavailableView(title, systemImage: symbol, description: Text(message)) }
}
struct ParticipantPicker: View {
    @EnvironmentObject var store: RhythmStore
    @Binding var ids: [UUID]
    var body: some View {
        Section("Participantes") {
            ForEach(store.members) { member in
                Toggle(member.title, isOn: Binding(get: { ids.contains(member.id) }, set: { on in
                    if on { ids.append(member.id) } else { ids.removeAll { $0 == member.id } }
                }))
            }
            if ids.isEmpty { Text("Sem seleção: meta do casal ou atividade de todos.").font(.caption).foregroundStyle(.secondary) }
        }
    }
}
struct GoalRow: View {
    @EnvironmentObject var store: RhythmStore
    let goal: RhythmRecord
    var body: some View {
        let value = store.progress(goal)
        VStack(alignment: .leading, spacing: 8) {
            HStack { Image(systemName: goal.category.symbol).foregroundStyle(.tint); Text(goal.title).font(.headline) }
            Text(store.memberNames(goal.participants)).font(.caption).foregroundStyle(.secondary)
            if goal.metric == .deadline {
                Label(goal.completed ? "Concluída" : "Até \(goal.end.formatted(date: .abbreviated, time: .omitted))", systemImage: goal.completed ? "checkmark.circle.fill" : "calendar")
            } else {
                ProgressView(value: min(value, goal.target), total: max(0.001, goal.target))
                Text("\(value.formatted(.number.precision(.fractionLength(0...1)))) de \(goal.target.formatted()) \(goal.metric == .hours ? "h" : "vezes") nesta semana").font(.subheadline).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 6).accessibilityElement(children: .combine)
    }
}
struct TimerCard: View {
    @EnvironmentObject var store: RhythmStore
    var body: some View {
        if let timer = store.timer {
            RhythmCard {
                Label("Seu momento em andamento", systemImage: timer.session.category.symbol).font(.subheadline).foregroundStyle(.secondary)
                Text(timer.session.title).font(.headline)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Duration.seconds(timer.elapsed(at: context.date)).formatted(.time(pattern: .hourMinuteSecond))).font(.system(.largeTitle, design: .rounded)).monospacedDigit()
                }.accessibilityLabel("Tempo da atividade")
                HStack {
                    Button(timer.runningSince == nil ? "Retomar" : "Pausar") { store.toggleTimer() }.buttonStyle(.bordered)
                    Button("Concluir", systemImage: "checkmark") { store.finishTimer() }.buttonStyle(.borderedProminent)
                }
            }
        }
    }
}
struct EventRow: View {
    @EnvironmentObject var store: RhythmStore
    let occurrence: Occurrence
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 3) {
                Text(occurrence.start, format: .dateTime.hour().minute()).font(.headline).monospacedDigit()
                Image(systemName: occurrence.record.category.symbol).foregroundStyle(.tint)
            }.frame(minWidth: 55)
            VStack(alignment: .leading, spacing: 4) {
                Text(occurrence.record.title).font(.headline)
                Text("\(occurrence.record.category.title) · \(store.memberNames(occurrence.record.participants))").font(.caption).foregroundStyle(.secondary)
                if !occurrence.record.notes.isEmpty { Text(occurrence.record.notes).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
            }
        }.padding(.vertical, 6).accessibilityElement(children: .combine)
    }
}
