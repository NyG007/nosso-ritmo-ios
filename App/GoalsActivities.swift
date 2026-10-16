import SwiftUI

struct GoalsView: View {
    @EnvironmentObject var store: RhythmStore
    @State var creating = false
    @State var editing: RhythmRecord?
    var body: some View {
        List {
            Section("Nossa rotina") {
                ForEach(Category.allCases.filter { $0 != .couple }) { category in
                    NavigationLink { ActivityView(category: category) } label: { Label(category.title, systemImage: category.symbol) }
                }
            }
            Section("Nossos objetivos") {
                if store.items(.goal).isEmpty { Text("Comecem com uma meta que faça sentido para vocês. Nenhuma quantidade de horas é obrigatória.").foregroundStyle(.secondary) }
                ForEach(store.items(.goal)) { goal in
                    Button { editing = goal } label: { GoalRow(goal: goal) }.buttonStyle(.plain)
                        .swipeActions { Button("Excluir", role: .destructive) { store.delete(goal) } }
                }
            }
        }.navigationTitle("Metas")
            .toolbar { Button("Nova meta", systemImage: "plus") { creating = true } }
            .sheet(isPresented: $creating) { GoalEditor() }
            .sheet(item: $editing) { GoalEditor(item: $0) }
    }
}

struct GoalEditor: View {
    @EnvironmentObject var store: RhythmStore
    @Environment(\.dismiss) var dismiss
    @State var item: RhythmRecord
    let baseline: RhythmRecord?
    init(item: RhythmRecord? = nil) { _item = State(initialValue: item ?? RhythmRecord(kind: .goal, title: "")); baseline = item }
    var body: some View {
        NavigationStack {
            Form {
                Section("Objetivo") {
                    TextField("Título da meta", text: $item.title)
                    Picker("Categoria", selection: $item.category) { ForEach(Category.allCases) { Text($0.title).tag($0) } }
                    Picker("Acompanhar", selection: $item.metric) { ForEach(GoalMetric.allCases, id: \.self) { Text($0.title).tag($0) } }
                    if item.metric == .deadline {
                        DatePicker("Concluir até", selection: $item.end, displayedComponents: .date)
                        Toggle("Meta concluída", isOn: $item.completed)
                    } else {
                        TextField(item.metric == .hours ? "Horas por semana" : "Vezes por semana", value: $item.target, format: .number).keyboardType(.decimalPad)
                    }
                    TextField("Por que isso importa para nós?", text: $item.notes, axis: .vertical)
                }
                ParticipantPicker(ids: $item.participants)
                Section { Text("Sem participantes selecionados: meta conjunta. Com uma pessoa: meta individual. Com as duas: apenas atividades feitas juntas contam. Toda meta é visível aos dois.").font(.footnote) }
                if let message = RhythmValidation.message(for: item) { Text(message).foregroundStyle(.secondary) }
            }.navigationTitle("Nossa meta").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Salvar") { if store.save(item, baseline: baseline) { dismiss() } }.disabled(RhythmValidation.message(for: item) != nil) }
                }
        }
    }
}

struct ActivityView: View {
    @EnvironmentObject var store: RhythmStore
    let category: Category
    @State var manual = false
    @State var timerSetup = false
    @State var templateEditor = false
    @State var editing: RhythmRecord?
    @State var scheduling: RhythmRecord?
    var templates: [RhythmRecord] { store.items(category == .study ? .subject : .workout).filter { $0.category == category } }
    var body: some View {
        List {
            if store.timer != nil { Section { TimerCard().listRowInsets(EdgeInsets()) } }
            Section {
                Button("Iniciar cronômetro", systemImage: "timer") { timerSetup = true }.disabled(store.timer != nil)
                Button("Registrar atividade realizada", systemImage: "plus.circle") { manual = true }
            }
            if category == .study || category == .gym {
                Section(category == .study ? "Matérias" : "Treinos") {
                    ForEach(templates) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            Button { editing = item } label: { VStack(alignment: .leading) { Text(item.title).font(.headline); if !item.notes.isEmpty { Text(item.notes).font(.caption).foregroundStyle(.secondary) } } }.buttonStyle(.plain)
                            HStack {
                                Button("Agendar", systemImage: "calendar.badge.plus") { scheduling = item }.buttonStyle(.bordered)
                                Button("Começar", systemImage: "play") {
                                    store.startTimer(category: category, title: item.title, participants: store.myID.map { [$0] } ?? [], templateID: item.id)
                                }.buttonStyle(.bordered).disabled(store.timer != nil)
                            }
                        }.swipeActions { Button("Excluir", role: .destructive) { store.delete(item) } }
                    }
                    Button(category == .study ? "Adicionar matéria" : "Adicionar treino", systemImage: "plus") { templateEditor = true }
                }
            }
            Section("Metas desta categoria") {
                let goals = store.items(.goal).filter { $0.category == category }
                if goals.isEmpty { Text("Definam a meta na aba Metas.").foregroundStyle(.secondary) }
                ForEach(goals) { GoalRow(goal: $0) }
            }
            Section("Histórico realizado") {
                let sessions = store.items(.session).filter { $0.category == category }.sorted { $0.start > $1.start }
                if sessions.isEmpty { Text("Os momentos concluídos aparecem aqui.").foregroundStyle(.secondary) }
                ForEach(sessions) { session in
                    Button { editing = session } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(session.title).font(.headline)
                            Text("\(session.start.formatted(date: .abbreviated, time: .shortened)) · \(Int(session.duration / 60)) min").font(.caption).foregroundStyle(.secondary)
                            Text(store.memberNames(session.participants)).font(.caption).foregroundStyle(.secondary)
                        }
                    }.buttonStyle(.plain).swipeActions { Button("Excluir", role: .destructive) { store.delete(session) } }
                }
            }
        }.navigationTitle(category.title)
            .sheet(isPresented: $manual) { SessionEditor(category: category) }
            .sheet(isPresented: $timerSetup) { TimerSetup(category: category) }
            .sheet(isPresented: $templateEditor) { SimpleEditor(kind: category == .study ? .subject : .workout, category: category) }
            .sheet(item: $editing) { item in
                if item.kind == .session { SessionEditor(category: category, item: item) }
                else { SimpleEditor(kind: item.kind, category: category, item: item) }
            }
            .sheet(item: $scheduling) { template in
                let event: RhythmRecord = {
                    var value = RhythmRecord(kind: .event, title: template.title)
                    value.category = category; value.parentID = template.id; value.notes = template.notes; return value
                }()
                EventEditor(date: Date(), item: event)
            }
    }
}

struct SessionEditor: View {
    @EnvironmentObject var store: RhythmStore
    @Environment(\.dismiss) var dismiss
    @State var item: RhythmRecord
    @State var minutes: Double
    let baseline: RhythmRecord?
    init(category: Category, item: RhythmRecord? = nil) {
        var value = item ?? RhythmRecord(kind: .session, title: "")
        value.category = category; value.completed = true
        _item = State(initialValue: value); _minutes = State(initialValue: item.map { $0.duration / 60 } ?? 30)
        baseline = item
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Atividade realizada") {
                    TextField(item.category == .streaming ? "Filme ou série" : "O que vocês fizeram?", text: $item.title)
                    DatePicker("Início", selection: $item.start)
                    TextField("Duração em minutos", value: $minutes, format: .number).keyboardType(.decimalPad)
                    TextField("Observações", text: $item.notes, axis: .vertical)
                }
                ParticipantPicker(ids: $item.participants)
            }.navigationTitle("Registrar momento").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Salvar") {
                        item.duration = minutes * 60
                        if baseline == nil || baseline?.duration != item.duration || baseline?.start != item.start {
                            item.end = item.start.addingTimeInterval(item.duration)
                        }
                        if item.participants.isEmpty { item.participants = store.members.map(\.id) }
                        if store.save(item, baseline: baseline) { dismiss() }
                    }.disabled(minutes <= 0 || !minutes.isFinite || item.title.trimmingCharacters(in: .whitespaces).isEmpty) }
                }
        }
    }
}

struct TimerSetup: View {
    @EnvironmentObject var store: RhythmStore
    @Environment(\.dismiss) var dismiss
    let category: Category
    @State var title = ""
    @State var ids: [UUID] = []
    var body: some View {
        NavigationStack {
            Form {
                TextField(category == .streaming ? "Filme ou série" : "Nome da atividade", text: $title)
                ParticipantPicker(ids: $ids)
                Text("O cronômetro fica neste aparelho. Ao concluir, o registro será compartilhado com os dois. Não é necessário iniciar outro cronômetro no segundo iPhone.").font(.footnote)
            }.navigationTitle("Um tempo para \(category.title.lowercased())")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Iniciar") { store.startTimer(category: category, title: title, participants: ids.isEmpty ? store.members.map(\.id) : ids); dismiss() } }
                }
        }
    }
}

struct SimpleEditor: View {
    @EnvironmentObject var store: RhythmStore
    @Environment(\.dismiss) var dismiss
    @State var item: RhythmRecord
    let baseline: RhythmRecord?
    init(kind: RecordKind, category: Category = .couple, parentID: UUID? = nil, item: RhythmRecord? = nil) {
        var value = item ?? RhythmRecord(kind: kind, title: "")
        if item == nil { value.category = category; value.parentID = parentID }
        _item = State(initialValue: value)
        baseline = item
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField(item.kind == .trip ? "Destino ou nome da viagem" : "Título", text: $item.title)
                TextField(item.kind == .music ? "Dedicatória" : "Observações", text: $item.notes, axis: .vertical)
                if [.trip, .itinerary].contains(item.kind) {
                    DatePicker("Início", selection: $item.start)
                    DatePicker("Término", selection: $item.end)
                }
                if [.trip, .expense].contains(item.kind) {
                    TextField(item.kind == .trip ? "Orçamento previsto (R$)" : "Valor (R$)", value: $item.amount, format: .number).keyboardType(.decimalPad)
                }
                if item.kind == .expense { DatePicker("Data", selection: $item.start, displayedComponents: .date) }
                if item.kind == .music {
                    TextField("Link da música", text: $item.url).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("Links HTTPS do Spotify, Apple Music ou YouTube. A música abre no serviço de origem.").font(.footnote).foregroundStyle(.secondary)
                }
                if let message = RhythmValidation.message(for: item) { Text(message).foregroundStyle(.secondary) }
            }.navigationTitle(editorTitle).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Salvar") {
                        if item.kind == .music && item.participants.isEmpty { item.participants = store.myID.map { [$0] } ?? [] }
                        if store.save(item, baseline: baseline) {
                            if item.kind == .itinerary && item.linkedID != nil { store.linkItinerary(item) }
                            dismiss()
                        }
                    }.disabled(RhythmValidation.message(for: item) != nil) }
                }
        }
    }
    var editorTitle: String {
        switch item.kind {
        case .subject: return "Matéria"
        case .workout: return "Treino"
        case .trip: return "Viagem"
        case .itinerary: return "Roteiro"
        case .checklist: return "Checklist"
        case .expense: return "Despesa"
        case .music: return "Música para nós"
        default: return "Editar"
        }
    }
}
