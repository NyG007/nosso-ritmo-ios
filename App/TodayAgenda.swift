import SwiftUI

struct TodayView: View {
    @EnvironmentObject var store: RhythmStore
    @State var selected: Category?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide)).font(.subheadline).foregroundStyle(.secondary)
                    Text("A vida acontece\nnos nossos encontros.").font(.system(.largeTitle, design: .serif))
                    Text(store.members.map(\.title).joined(separator: " & ")).font(.headline).foregroundStyle(.tint)
                }.padding(.vertical, 8)
                TimerCard()
                RhythmCard {
                    Text("Nosso próximo momento").font(.headline)
                    if let next = store.nextEvents().first {
                        Button { store.selectedDate = next.start; store.selectedTab = 1 } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(next.start, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(.secondary)
                                EventRow(occurrence: next)
                            }
                        }.buttonStyle(.plain)
                    } else { Text("Que tal reservar um tempo para vocês?").foregroundStyle(.secondary) }
                    Button("Abrir agenda", systemImage: "arrow.up.right") { store.selectedTab = 1 }
                }
                Text("Cuidar da nossa rotina").font(.title3.bold())
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 12) {
                    ForEach(Category.allCases.filter { $0 != .couple }) { category in
                        NavigationLink { ActivityView(category: category) } label: {
                            RhythmCard { Image(systemName: category.symbol).font(.title2); Text(category.title).font(.headline) }
                        }.buttonStyle(.plain)
                    }
                }
                if !store.items(.goal).isEmpty {
                    RhythmCard { Text("Uma semana no nosso ritmo").font(.headline); ForEach(store.items(.goal).prefix(3)) { GoalRow(goal: $0) } }
                }
                Text(store.persistence.status).font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }.rhythmSurface().navigationTitle("Hoje").navigationBarTitleDisplayMode(.inline)
    }
}

struct AgendaView: View {
    @EnvironmentObject var store: RhythmStore
    @State var newEvent = false
    @State var selection: Occurrence?
    var body: some View {
        List {
            Section {
                DatePicker("Dia", selection: $store.selectedDate, displayedComponents: .date).datePickerStyle(.graphical)
            }.listRowInsets(EdgeInsets())
            Section(store.selectedDate.formatted(.dateTime.weekday(.wide).day().month(.wide))) {
                let interval = store.calendar.dateInterval(of: .day, for: store.selectedDate)!
                let events = store.occurrences(in: interval)
                if events.isEmpty { Text("Um dia com espaço para novos planos.").foregroundStyle(.secondary) }
                ForEach(events) { event in
                    Button { selection = event } label: { EventRow(occurrence: event) }.buttonStyle(.plain)
                        .listRowBackground(store.highlightedID == event.record.id ? Color.accentColor.opacity(0.12) : nil)
                }
            }
        }.navigationTitle("Agenda")
            .toolbar { Button("Novo compromisso", systemImage: "plus") { newEvent = true } }
            .sheet(isPresented: $newEvent) { EventEditor(date: store.selectedDate) }
            .sheet(item: $selection) { OccurrenceEditor(occurrence: $0) }
    }
}

struct EventEditor: View {
    @EnvironmentObject var store: RhythmStore
    @Environment(\.dismiss) var dismiss
    @State var item: RhythmRecord
    var onSave: ((RhythmRecord) -> Bool)?
    init(date: Date, item: RhythmRecord? = nil, onSave: ((RhythmRecord) -> Bool)? = nil) {
        var event = item ?? RhythmRecord(kind: .event, title: "")
        if item == nil { event.start = date; event.end = date.addingTimeInterval(3600) }
        _item = State(initialValue: event); self.onSave = onSave
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Compromisso") {
                    TextField("Título", text: $item.title)
                    Picker("Categoria", selection: $item.category) { ForEach(Category.allCases) { Text($0.title).tag($0) } }
                    DatePicker("Início", selection: $item.start)
                    DatePicker("Término", selection: $item.end)
                    Picker("Repetição", selection: $item.recurrence) { ForEach(RepeatRule.allCases, id: \.self) { Text($0.title).tag($0) } }
                    Picker("Lembrete", selection: $item.reminderMinutes) {
                        Text("Sem lembrete").tag(-1); Text("Na hora").tag(0); Text("15 minutos antes").tag(15); Text("1 hora antes").tag(60); Text("1 dia antes").tag(1440)
                    }
                    TextField("Observações", text: $item.notes, axis: .vertical)
                }
                ParticipantPicker(ids: $item.participants)
                if let error = RhythmValidation.message(for: item) { Section { Text(error).foregroundStyle(.secondary) } }
            }.navigationTitle("Compromisso").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Salvar") {
                        if item.participants.isEmpty { item.participants = store.members.map(\.id) }
                        if onSave?(item) ?? store.save(item) { dismiss() }
                    }.disabled(RhythmValidation.message(for: item) != nil) }
                }
        }
    }
}

struct OccurrenceEditor: View {
    @EnvironmentObject var store: RhythmStore
    @Environment(\.dismiss) var dismiss
    let occurrence: Occurrence
    @State var following = false
    @State var edit = false
    @State var confirmDelete = false
    var body: some View {
        NavigationStack {
            Form {
                Section { EventRow(occurrence: occurrence); Text(occurrence.start.formatted(date: .complete, time: .shortened)); Text("Até \(occurrence.end.formatted(date: .abbreviated, time: .shortened))") }
                if occurrence.record.recurrence != .never {
                    Picker("Aplicar a", selection: $following) { Text("Só esta ocorrência").tag(false); Text("Esta e próximas").tag(true) }
                }
                Button("Editar compromisso") { edit = true }
                Button("Excluir", role: .destructive) { confirmDelete = true }
            }.navigationTitle("Nosso compromisso").toolbar { Button("Fechar") { dismiss() } }
                .confirmationDialog("Excluir este compromisso?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Excluir", role: .destructive) { store.editOccurrence(occurrence, edited: nil, following: following); dismiss() }
                }
                .sheet(isPresented: $edit) {
                    var edited = occurrence.record
                    let _ = { edited.start = occurrence.start; edited.end = occurrence.end }()
                    EventEditor(date: occurrence.start, item: edited) { item in
                        store.editOccurrence(occurrence, edited: item, following: following)
                        if store.error == nil { dismiss(); return true }; return false
                    }
                }
        }
    }
}
