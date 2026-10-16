import SwiftUI
import CoreData
import CloudKit
import Combine
import CryptoKit

@MainActor
final class RhythmStore: ObservableObject {
    let persistence: Persistence
    @Published var records: [RhythmRecord] = []
    @Published var root: NSManagedObject?
    @Published var error: String?
    @Published var timer: ActiveTimer?
    @Published var myID: UUID?
    @Published var share: CKShare?
    @Published var showingShare = false
    @Published var invitationURL: URL?
    @Published var waitingForSharedSpace = false
    @Published var busy = false
    @Published var selectedTab = 0
    @Published var selectedDate = Date()
    @Published var highlightedID: UUID?
    @Published var profileName = ""
    private var subscriptions = Set<AnyCancellable>()
    private var identity = ""
    private var acceptingInvite = false
    var calendar: Calendar { CalendarEngine.calendar() }
    var members: [RhythmRecord] { items(.member).sorted { $0.start < $1.start } }
    var storageKey: String { "timer-\(persistence.demo)-\((root?.value(forKey: "id") as? UUID)?.uuidString ?? "none")" }
    var remindersEnabled: Bool { UserDefaults.standard.bool(forKey: "remindersEnabled") }

    init(demo: Bool) {
        persistence = Persistence(demo: demo)
        persistence.$loaded.filter { $0 }.sink { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.reload()
                if demo && self.root == nil { self.createSpace(name: "Alex", demo: true) }
                await self.identify()
            }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: persistence.context)
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.reload() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.reload() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: .rhythmError).sink { [weak self] note in self?.error = note.object as? String }.store(in: &subscriptions)
    }

    func items(_ kind: RecordKind) -> [RhythmRecord] { records.filter { $0.kind == kind && !$0.deleted } }
    func memberNames(_ ids: [UUID]) -> String {
        ids.isEmpty ? "Casal" : members.filter { ids.contains($0.id) }.map(\.title).joined(separator: " e ")
    }
    func occurrences(in interval: DateInterval) -> [Occurrence] { CalendarEngine.occurrences(records: records, in: interval, calendar: calendar) }
    func progress(_ goal: RhythmRecord) -> Double { GoalEngine.progress(goal: goal, records: records, now: Date(), calendar: calendar) }
    func nextEvents() -> [Occurrence] {
        occurrences(in: DateInterval(start: Date(), end: calendar.date(byAdding: .day, value: 30, to: Date())!))
    }
    func objects() throws -> [NSManagedObject] {
        guard let root else { return [] }
        let request = NSFetchRequest<NSManagedObject>(entityName: "Entry")
        request.predicate = NSPredicate(format: "space == %@", root)
        return try persistence.context.fetch(request)
    }
    func reload() {
        guard persistence.loaded else { return }
        do {
            let roots = try persistence.roots()
            if root?.isDeleted != false || !roots.contains(where: { $0.objectID == root?.objectID }) {
                root = roots.first { $0.objectID.persistentStore == persistence.sharedStore } ?? roots.first
            }
            let fetched = try objects().map(RhythmRecord.init(object:))
            records = Array(Dictionary(fetched.map { ($0.id, $0) }, uniquingKeysWith: { $0.updatedAt >= $1.updatedAt ? $0 : $1 }).values)
            if root?.objectID.persistentStore == persistence.sharedStore { waitingForSharedSpace = false }
            if let member = members.first(where: { $0.identity == identity && !identity.isEmpty }) { myID = member.id; profileName = member.title }
            else { myID = nil }
            timer = UserDefaults.standard.data(forKey: storageKey).flatMap { try? JSONDecoder().decode(ActiveTimer.self, from: $0) }
            refreshServices()
        } catch { self.error = error.localizedDescription }
    }

    func createSpace(name: String, demo: Bool = false) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "Informe seu nome."; return }
        guard root == nil, let store = persistence.privateStore else { return }
        let object = NSEntityDescription.insertNewObject(forEntityName: "Space", into: persistence.context)
        persistence.context.assign(object, to: store)
        object.setValue(UUID(), forKey: "id"); object.setValue("Nosso Ritmo", forKey: "title")
        root = object
        do { try persistence.save() } catch { self.error = error.localizedDescription; persistence.context.rollback(); root = nil; return }
        if demo { identity = "demo-alex" }
        registerMember(name)
        if demo { seedDemo() }
    }
    func identify() async {
        if persistence.demo { identity = "demo-alex"; reload(); return }
        do {
            let cloud = CKContainer(identifier: AppConfig.cloudID)
            let status = try await cloud.accountStatus()
            guard status == .available else { throw RhythmError.message("Entre no iCloud nos Ajustes do iPhone para compartilhar o casal.") }
            identity = try await cloud.userRecordID().recordName
            reload()
        } catch { self.error = error.localizedDescription }
    }
    func registerMember(_ name: String) {
        guard !identity.isEmpty else { error = "Aguarde a identificação do iCloud e tente novamente."; return }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "Informe seu nome."; return }
        if var current = members.first(where: { $0.identity == identity }) { current.title = name; _ = save(current); return }
        guard members.count < 2 else { error = "Este espaço já tem duas pessoas."; return }
        var member = RhythmRecord(kind: .member, title: name); member.identity = identity
        if save(member) { myID = member.id; profileName = name }
    }
    @discardableResult func save(_ source: RhythmRecord) -> Bool {
        guard let root, let store = root.objectID.persistentStore else { error = "Crie ou aceite um espaço do casal primeiro."; return false }
        if let message = RhythmValidation.message(for: source), !source.deleted { error = message; return false }
        do {
            var value = source; value.updatedAt = Date()
            let existing = try objects().first { $0.value(forKey: "id") as? UUID == value.id }
            let object = existing ?? NSEntityDescription.insertNewObject(forEntityName: "Entry", into: persistence.context)
            if existing == nil { persistence.context.assign(object, to: store); object.setValue(root, forKey: "space") }
            value.write(to: object, previous: existing.map(RhythmRecord.init(object:)))
            try persistence.save(); reload(); return true
        } catch { self.error = error.localizedDescription; persistence.context.rollback(); reload(); return false }
    }
    func delete(_ item: RhythmRecord) {
        var value = item; value.deleted = true
        guard save(value) else { return }
        // Keep itinerary links and all trip children consistent.
        if item.kind == .itinerary, let linked = item.linkedID, let event = records.first(where: { $0.id == linked && !$0.deleted }) { delete(event) }
        if item.kind == .trip { for child in records.filter({ $0.parentID == item.id && !$0.deleted }) { delete(child) } }
        if item.kind == .event {
            for child in items(.itinerary).filter({ $0.linkedID == item.id }) { var changed = child; changed.linkedID = nil; _ = save(changed) }
        }
    }
    func editOccurrence(_ occurrence: Occurrence, edited: RhythmRecord?, following: Bool) {
        let original = occurrence.record
        if original.recurrence == .never { if let edited { _ = save(edited) } else { delete(original) }; return }
        if following {
            var truncated = records.first(where: { $0.id == original.id }) ?? original
            truncated.repeatUntil = occurrence.originalStart
            guard save(truncated) else { return }
            for exception in items(.exception).filter({ $0.parentID == original.id && ($0.originalDate ?? .distantPast) >= occurrence.originalStart }) { delete(exception) }
            if var replacement = edited { replacement.id = UUID(); replacement.repeatUntil = original.repeatUntil; _ = save(replacement) }
        } else {
            let existing = items(.exception).first { $0.parentID == original.id && $0.originalDate == occurrence.originalStart }
            _ = save(CalendarEngine.exception(for: occurrence, edited: edited, existingID: existing?.id))
        }
    }
    func startTimer(category: Category, title: String, participants: [UUID], templateID: UUID? = nil) {
        guard timer == nil else { error = "Conclua o cronômetro atual antes de iniciar outro."; return }
        var session = RhythmRecord(kind: .session, title: title.isEmpty ? category.title : title)
        session.category = category; session.participants = participants; session.parentID = templateID
        session.start = Date(); timer = ActiveTimer(session: session); persistTimer()
    }
    func toggleTimer() {
        guard var value = timer else { return }
        if value.runningSince == nil { value.resume(at: Date()) } else { value.pause(at: Date()) }
        timer = value; persistTimer()
    }
    func finishTimer() {
        guard let value = timer else { return }
        if save(value.finish(at: Date())) { timer = nil; persistTimer() }
    }
    func persistTimer() {
        if let timer, let data = try? JSONEncoder().encode(timer) { UserDefaults.standard.set(data, forKey: storageKey) }
        else { UserDefaults.standard.removeObject(forKey: storageKey) }
        objectWillChange.send()
    }
    func linkItinerary(_ item: RhythmRecord) {
        // Stable ID makes retries and offline additions from both devices idempotent.
        let digest = Array(SHA256.hash(data: Data("nosso-ritmo/itinerary/\(item.id.uuidString)".utf8)))
        let hex = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        let stableID = UUID(uuidString: "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20).prefix(12))")!
        let eventID = item.linkedID ?? stableID
        var event = records.first { $0.id == eventID && !$0.deleted } ?? RhythmRecord(kind: .event, title: item.title)
        event.id = eventID
        event.title = item.title; event.notes = item.notes; event.start = item.start; event.end = item.end
        event.category = .couple; event.participants = members.map(\.id)
        guard save(event) else { return }
        var updated = item; updated.linkedID = event.id; _ = save(updated)
    }
    func prepareShare() async {
        guard !persistence.demo, let root else { error = "Compartilhamento disponível no modo iCloud."; return }
        busy = true; defer { busy = false }
        do {
            guard root.objectID.persistentStore == persistence.privateStore else { throw RhythmError.message("O convite é gerenciado por quem criou o espaço.") }
            showingShare = true
        } catch { self.error = error.localizedDescription }
    }
    func invite(email: String) async {
        guard let root else { return }
        busy = true; defer { busy = false }
        do { invitationURL = try await persistence.invite(root: root, email: email.trimmingCharacters(in: .whitespacesAndNewlines)) }
        catch { self.error = error.localizedDescription }
    }
    func accept(_ metadata: CKShare.Metadata) async {
        guard !persistence.demo else { error = "Saia da demonstração e abra o convite novamente no modo iCloud."; return }
        guard !acceptingInvite else { return }
        guard metadata.share.participants.count <= 2 else { error = "O convite não corresponde a um espaço para duas pessoas."; return }
        if let root, root.objectID.persistentStore == persistence.privateStore {
            error = "Você já criou um espaço. Use o convite em uma instalação sem espaço próprio para evitar unir dois históricos."; return
        }
        acceptingInvite = true; busy = true; defer { acceptingInvite = false; busy = false }
        do { waitingForSharedSpace = true; try await persistence.accept(metadata); reload(); await identify() }
        catch { waitingForSharedSpace = false; self.error = error.localizedDescription }
    }
    func leave() async {
        guard let root else { return }
        busy = true; defer { busy = false }
        do {
            try await persistence.leave(root: root)
            UserDefaults.standard.removeObject(forKey: storageKey)
            self.root = nil; records = []; timer = nil; myID = nil; WidgetBridge.clear(); reload()
        } catch { self.error = error.localizedDescription }
    }
    func refreshServices() {
        let now = Date()
        let upcoming = nextEvents()
        let weekEnd = calendar.dateInterval(of: .weekOfYear, for: now)?.end ?? now
        let goals = items(.goal).filter { [.outdoors, .streaming].contains($0.category) && $0.metric == .hours }
        let snapshot = WidgetSnapshot(generatedAt: now, weekEnd: weekEnd, theme: UserDefaults.standard.string(forKey: "theme") ?? "system",
            events: upcoming.prefix(12).map { WidgetEvent(id: $0.id, title: $0.record.title, date: $0.start, url: URL(string: "nossoritmo://event/\($0.record.id.uuidString)?at=\($0.start.timeIntervalSince1970)")!) },
            goals: goals.prefix(2).map { WidgetGoal(id: $0.id.uuidString, title: "\($0.category.title) · \(memberNames($0.participants))", value: progress($0), target: $0.target) })
        // Missing App Groups do not prevent the app from saving local records.
        do { try WidgetBridge.write(snapshot) } catch { /* surfaced by widget setup screen / documentation */ }
        Task { await ReminderService.shared.update(events: upcoming, enabled: remindersEnabled && root != nil, now: now) }
    }
    func route(_ url: URL) {
        guard url.scheme == "nossoritmo" else { return }
        if url.host == "event", let id = UUID(uuidString: url.lastPathComponent) {
            selectedTab = 1; highlightedID = id
            if let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "at" })?.value,
               let timestamp = Double(value), timestamp.isFinite, abs(timestamp) < 1e11 {
                selectedDate = Date(timeIntervalSince1970: timestamp)
            } else if let next = nextEvents().first(where: { $0.record.id == id }) { selectedDate = next.start }
            else if let record = records.first(where: { $0.id == id }) { selectedDate = record.start }
        } else if url.host == "goals" { selectedTab = 2 }
        else if url.host == "agenda" { selectedTab = 1 }
    }
    func seedDemo() {
        var partner = RhythmRecord(kind: .member, title: "Dani"); partner.identity = "demo-dani"; _ = save(partner)
        let ids = members.map(\.id)
        var event = RhythmRecord(kind: .event, title: "Um café sem pressa")
        event.start = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: Date())!.addingTimeInterval(86400)
        event.end = event.start.addingTimeInterval(3600); event.participants = ids; _ = save(event)
        for category in [Category.outdoors, .streaming] {
            var goal = RhythmRecord(kind: .goal, title: category == .outdoors ? "Mais céu, mais nós" : "Nossa sessão de cinema")
            goal.category = category; goal.target = category == .outdoors ? 3 : 2; goal.participants = ids; _ = save(goal)
        }
        var subject = RhythmRecord(kind: .subject, title: "Inglês"); subject.category = .study; _ = save(subject)
        var workout = RhythmRecord(kind: .workout, title: "Treino de força"); workout.category = .gym; _ = save(workout)
        var music = RhythmRecord(kind: .music, title: "Uma música para o nosso dia")
        music.url = "https://music.apple.com/br/browse"; music.notes = "Lembrei de você quando ouvi 💕"; music.participants = myID.map { [$0] } ?? []; _ = save(music)
        var trip = RhythmRecord(kind: .trip, title: "Fim de semana na serra")
        trip.start = calendar.date(byAdding: .day, value: 30, to: Date())!; trip.end = trip.start.addingTimeInterval(172800); trip.amount = 1500; _ = save(trip)
    }
}
