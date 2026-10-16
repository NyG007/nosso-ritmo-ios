import SwiftUI

struct TripsView: View {
    @EnvironmentObject var store: RhythmStore
    @State var creating = false
    var body: some View {
        List {
            if store.items(.trip).isEmpty { EmptyHint(title: "Nosso próximo destino", message: "Uma escapada de fim de semana ou a viagem dos sonhos começa aqui.", symbol: "suitcase.rolling") }
            ForEach(store.items(.trip).sorted { $0.start < $1.start }) { trip in
                NavigationLink { TripDetail(id: trip.id) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(trip.title, systemImage: "mappin.and.ellipse").font(.headline)
                        Text("\(trip.start.formatted(date: .abbreviated, time: .omitted)) — \(trip.end.formatted(date: .abbreviated, time: .omitted))").font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }
            }
        }.navigationTitle("Viagens").toolbar { Button("Nova viagem", systemImage: "plus") { creating = true } }
            .sheet(isPresented: $creating) { SimpleEditor(kind: .trip) }
    }
}

struct TripDetail: View {
    @EnvironmentObject var store: RhythmStore
    @Environment(\.dismiss) var dismiss
    let id: UUID
    @State var newKind: RecordKind?
    @State var editItem: RhythmRecord?
    @State var confirmDelete = false
    func children(_ kind: RecordKind) -> [RhythmRecord] { store.items(kind).filter { $0.parentID == id }.sorted { $0.start < $1.start } }
    var body: some View {
        Group {
            if let trip = store.records.first(where: { $0.id == id && !$0.deleted }) {
                List {
                    Section("Nossa viagem") {
                        Text("\(trip.start.formatted(date: .abbreviated, time: .omitted)) — \(trip.end.formatted(date: .abbreviated, time: .omitted))")
                        if !trip.notes.isEmpty { Text(trip.notes) }
                        Button("Editar viagem") { editItem = trip }
                    }
                    Section("Orçamento") {
                        LabeledContent("Previsto", value: trip.amount.formatted(.currency(code: "BRL")))
                        let spent = children(.expense).reduce(0) { $0 + $1.amount }
                        LabeledContent("Realizado", value: spent.formatted(.currency(code: "BRL")))
                        LabeledContent("Disponível", value: (trip.amount - spent).formatted(.currency(code: "BRL")))
                    }
                    Section("Roteiro por dia") {
                        ForEach(children(.itinerary)) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(item.start, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(.secondary)
                                Button(item.title) { editItem = item }.font(.headline).buttonStyle(.plain)
                                if !item.notes.isEmpty { Text(item.notes).font(.subheadline) }
                                Button(item.linkedID == nil ? "Adicionar à agenda" : "Atualizar na agenda", systemImage: "calendar.badge.plus") { store.linkItinerary(item) }.font(.subheadline)
                            }.swipeActions { Button("Excluir", role: .destructive) { store.delete(item) } }
                        }
                        Button("Adicionar parada", systemImage: "plus") { newKind = .itinerary }
                    }
                    Section("Checklist") {
                        ForEach(children(.checklist)) { item in
                            HStack {
                                Button { var changed = item; changed.completed.toggle(); _ = store.save(changed) } label: {
                                    Image(systemName: item.completed ? "checkmark.circle.fill" : "circle").font(.title3)
                                }.buttonStyle(.borderless).accessibilityLabel(item.completed ? "Desmarcar \(item.title)" : "Concluir \(item.title)")
                                Button(item.title) { editItem = item }.buttonStyle(.plain).strikethrough(item.completed)
                            }.swipeActions { Button("Excluir", role: .destructive) { store.delete(item) } }
                        }
                        Button("Adicionar tarefa", systemImage: "plus") { newKind = .checklist }
                    }
                    Section("Despesas") {
                        ForEach(children(.expense)) { item in
                            Button { editItem = item } label: { LabeledContent(item.title, value: item.amount.formatted(.currency(code: "BRL"))) }.buttonStyle(.plain)
                                .swipeActions { Button("Excluir", role: .destructive) { store.delete(item) } }
                        }
                        Button("Adicionar despesa", systemImage: "plus") { newKind = .expense }
                    }
                    Button("Excluir viagem", role: .destructive) { confirmDelete = true }
                }.navigationTitle(trip.title)
                    .confirmationDialog("Excluir a viagem, roteiro, checklist e despesas?", isPresented: $confirmDelete, titleVisibility: .visible) {
                        Button("Excluir viagem", role: .destructive) { store.delete(trip); dismiss() }
                    }
            } else { EmptyHint(title: "Viagem removida", message: "Volte à lista de viagens.", symbol: "suitcase") }
        }
        .sheet(isPresented: Binding(get: { newKind != nil }, set: { if !$0 { newKind = nil } })) {
            if let newKind {
                let item: RhythmRecord = {
                    var value = RhythmRecord(kind: newKind, title: ""); value.parentID = id
                    if let trip = store.records.first(where: { $0.id == id }) { value.start = trip.start; value.end = trip.start.addingTimeInterval(3600) }
                    return value
                }()
                SimpleEditor(kind: newKind, parentID: id, item: item)
            }
        }
        .sheet(item: $editItem) { SimpleEditor(kind: $0.kind, item: $0) }
    }
}

struct TogetherView: View {
    @EnvironmentObject var store: RhythmStore
    @State var creating = false
    @State var editing: RhythmRecord?
    var body: some View {
        List {
            Section {
                Text(store.members.map(\.title).joined(separator: " & ")).font(.system(.title, design: .serif))
                Text("Nosso lugar para dividir o que toca a gente.").foregroundStyle(.secondary)
                NavigationLink { SettingsView() } label: { Label("Nosso espaço e preferências", systemImage: "slider.horizontal.3") }
            }
            Section("Músicas para nós") {
                if store.items(.music).isEmpty { Text("Uma música pode dizer muita coisa. Compartilhe a primeira.").foregroundStyle(.secondary) }
                ForEach(store.items(.music).sorted { $0.start > $1.start }) { music in
                    VStack(alignment: .leading, spacing: 10) {
                        Label(music.title, systemImage: "music.note").font(.headline)
                        if !music.notes.isEmpty { Text(music.notes).fontDesign(.serif) }
                        Text("De \(store.memberNames(music.participants)) · \(music.start.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary)
                        if RhythmValidation.isMusicURL(music.url), let url = URL(string: music.url) { Link(destination: url) { Label("Ouvir no serviço", systemImage: "arrow.up.right.square") } }
                        Button("Editar") { editing = music }.font(.caption)
                    }.padding(.vertical, 8).swipeActions { Button("Excluir", role: .destructive) { store.delete(music) } }
                }
            }
        }.navigationTitle("Nós")
            .toolbar { Button("Compartilhar música", systemImage: "plus") { creating = true } }
            .sheet(isPresented: $creating) { SimpleEditor(kind: .music) }
            .sheet(item: $editing) { SimpleEditor(kind: .music, item: $0) }
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: RhythmStore
    @ObservedObject var inbox = InviteInbox.shared
    @AppStorage("theme") var theme = "system"
    @AppStorage("storageMode") var mode = ""
    @AppStorage("remindersEnabled") var reminders = false
    @State var name = ""
    @State var confirmLeave = false
    var body: some View {
        Form {
            Section("Aparência neste iPhone") {
                Picker("Tema", selection: $theme) {
                    Text("Seguir sistema").tag("system"); Text("Claro").tag("light"); Text("Escuro").tag("dark"); Text("Rosa").tag("pink")
                }
            }
            Section("Vocês dois") {
                ForEach(store.members) { Label($0.title, systemImage: "person.crop.circle") }
                TextField("Meu nome", text: $name)
                Button("Atualizar meu nome") { store.registerMember(name) }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                if !store.persistence.demo {
                    Button(store.members.count < 2 ? "Convidar minha pessoa" : "Ver convite do casal", systemImage: "person.badge.plus") { Task { await store.prepareShare() } }.disabled(store.busy)
                    Text("Compartilhe apenas com sua pessoa, usando acesso privado de edição. O espaço foi feito para dois participantes.").font(.footnote).foregroundStyle(.secondary)
                    Button("Verificar conta e sincronização") { Task { await store.identify(); store.reload() } }
                }
                Text(store.persistence.status).font(.caption).foregroundStyle(.secondary)
            }
            Section("Lembretes neste iPhone") {
                Toggle("Notificar compromissos", isOn: Binding(get: { reminders }, set: { value in
                    if value {
                        Task {
                            do {
                                reminders = try await ReminderService.shared.authorization()
                                if !reminders { store.error = "Permita notificações nos Ajustes do iPhone para receber lembretes." }
                                store.refreshServices()
                            } catch { store.error = error.localizedDescription }
                        }
                    } else { reminders = false; store.refreshServices() }
                }))
                Link("Abrir ajustes do iPhone", destination: URL(string: UIApplication.openSettingsURLString)!)
            }
            Section("Widget") {
                Text("Mantenha a tela inicial pressionada, toque em Editar → Adicionar Widget e procure Nosso Ritmo. Escolha o tamanho pequeno ou médio.")
                Text("O iOS controla a atualização. Abra o app para atualizar os dados recebidos do casal.").font(.footnote).foregroundStyle(.secondary)
                if WidgetBridge.fileURL == nil { Label("App Group indisponível: confira a configuração no Xcode.", systemImage: "exclamationmark.triangle").font(.caption) }
            }
            Section("Este projeto") {
                Link("Código e instruções", destination: URL(string: "https://github.com/NyG007/nosso-ritmo-ios")!)
                Text("Calendário independente. Seus dados não são enviados ao GitHub.").font(.footnote)
                Button(store.persistence.demo ? "Sair da demonstração" : "Voltar à escolha de modo") {
                    WidgetBridge.clear(); mode = ""
                }
                if !store.persistence.demo {
                    Button("Sair / encerrar espaço compartilhado", role: .destructive) { confirmLeave = true }
                }
            }
        }.navigationTitle("Preferências").onAppear { name = store.profileName }
            .onChange(of: theme) { _, _ in store.refreshServices() }
            .confirmationDialog("Sair do compartilhamento?", isPresented: $confirmLeave, titleVisibility: .visible) {
                Button("Sair / encerrar compartilhamento", role: .destructive) { Task { await store.leave() } }
            } message: { Text("Se você é o proprietário, isso encerra o espaço compartilhado e remove seus registros. Se é convidado, remove seu acesso e a cópia local. Esta ação usa a remoção de zona do iCloud.") }
    }
}

struct InvitationView: View {
    @EnvironmentObject var store: RhythmStore
    @Environment(\.dismiss) var dismiss
    @State var email = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Um convite só para sua pessoa") {
                    Text("Informe o e-mail da conta iCloud dela. O link será privado, com permissão de edição, e só poderá ser aceito pela pessoa convidada.")
                    TextField("E-mail iCloud", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Preparar convite") { Task { await store.invite(email: email) } }.disabled(store.busy || !email.contains("@"))
                    if store.busy { ProgressView("Preparando no iCloud…") }
                }
                if let url = store.invitationURL {
                    Section("Enviar o link") {
                        ShareLink(item: url) { Label("Compartilhar convite", systemImage: "square.and.arrow.up") }
                        Text("Envie o link para a outra pessoa e peça para abri-lo no iPhone com o Nosso Ritmo instalado, no modo iCloud.").font(.footnote)
                    }
                }
                if let message = store.error { Section { Text(message).foregroundStyle(.red) } }
            }.navigationTitle("Nosso espaço").navigationBarTitleDisplayMode(.inline).toolbar { Button("Fechar") { dismiss() } }
        }
    }
}
