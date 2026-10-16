import CoreData
import CloudKit
import Combine

enum AppConfig {
    static var cloudID: String { Bundle.main.object(forInfoDictionaryKey: "CloudContainerIdentifier") as? String ?? "iCloud.com.nyg007.nossoritmo" }
    static var groupID: String { Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String ?? "group.com.nyg007.nossoritmo" }
}

/// Programmatic model: all attributes optional/defaulted, all relationships inverse, no unique constraints (CloudKit compatible).
enum RhythmModel {
    static let strings = ["kind", "title", "notes", "category", "participants", "identity", "recurrence", "metric", "url"]
    static let dates = ["start", "end", "repeatUntil", "originalDate", "updatedAt"]
    static let uuids = ["id", "parentID", "linkedID"]
    static let doubles = ["target", "duration", "amount"]
    // "deleted" would collide with NSManagedObject.isDeleted through KVC.
    static let bools = ["completed", "removed"]
    static func make() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        let space = NSEntityDescription(); space.name = "Space"; space.managedObjectClassName = "NSManagedObject"
        let entry = NSEntityDescription(); entry.name = "Entry"; entry.managedObjectClassName = "NSManagedObject"
        func attribute(_ name: String, _ type: NSAttributeType, _ defaultValue: Any? = nil) -> NSAttributeDescription {
            let value = NSAttributeDescription(); value.name = name; value.attributeType = type
            value.isOptional = true; value.defaultValue = defaultValue; return value
        }
        space.properties = [attribute("id", .UUIDAttributeType), attribute("title", .stringAttributeType, "Nosso Ritmo")]
        var fields: [NSPropertyDescription] = []
        fields.append(contentsOf: strings.map { attribute($0, .stringAttributeType, "") })
        fields.append(contentsOf: dates.map { attribute($0, .dateAttributeType) })
        fields.append(contentsOf: uuids.map { attribute($0, .UUIDAttributeType) })
        fields.append(contentsOf: doubles.map { attribute($0, .doubleAttributeType, 0) })
        fields.append(contentsOf: bools.map { attribute($0, .booleanAttributeType, false) })
        fields.append(attribute("reminderMinutes", .integer64AttributeType, -1))
        entry.properties = fields
        let children = NSRelationshipDescription(); children.name = "entries"; children.destinationEntity = entry
        children.minCount = 0; children.maxCount = 0; children.isOptional = true; children.deleteRule = .cascadeDeleteRule
        let root = NSRelationshipDescription(); root.name = "space"; root.destinationEntity = space
        root.minCount = 0; root.maxCount = 1; root.isOptional = true; root.deleteRule = .nullifyDeleteRule
        children.inverseRelationship = root; root.inverseRelationship = children
        space.properties.append(children); entry.properties.append(root)
        model.entities = [space, entry]; return model
    }
}

extension RhythmRecord {
    init(object: NSManagedObject) {
        self.init(kind: RecordKind(rawValue: object.value(forKey: "kind") as? String ?? "") ?? .event,
                  title: object.value(forKey: "title") as? String ?? "")
        id = object.value(forKey: "id") as? UUID ?? UUID()
        notes = object.value(forKey: "notes") as? String ?? ""
        category = Category(rawValue: object.value(forKey: "category") as? String ?? "") ?? .couple
        start = object.value(forKey: "start") as? Date ?? Date()
        end = object.value(forKey: "end") as? Date ?? start
        participants = (object.value(forKey: "participants") as? String ?? "").split(separator: ",").compactMap { UUID(uuidString: String($0)) }
        parentID = object.value(forKey: "parentID") as? UUID; linkedID = object.value(forKey: "linkedID") as? UUID
        identity = object.value(forKey: "identity") as? String ?? ""
        recurrence = RepeatRule(rawValue: object.value(forKey: "recurrence") as? String ?? "") ?? .never
        repeatUntil = object.value(forKey: "repeatUntil") as? Date; originalDate = object.value(forKey: "originalDate") as? Date
        reminderMinutes = (object.value(forKey: "reminderMinutes") as? NSNumber)?.intValue ?? -1
        metric = GoalMetric(rawValue: object.value(forKey: "metric") as? String ?? "") ?? .hours
        target = (object.value(forKey: "target") as? NSNumber)?.doubleValue ?? 1
        duration = (object.value(forKey: "duration") as? NSNumber)?.doubleValue ?? 0
        amount = (object.value(forKey: "amount") as? NSNumber)?.doubleValue ?? 0
        url = object.value(forKey: "url") as? String ?? ""
        completed = object.value(forKey: "completed") as? Bool ?? false
        deleted = object.value(forKey: "removed") as? Bool ?? false
        updatedAt = object.value(forKey: "updatedAt") as? Date ?? .distantPast
    }
    private var fields: [String: Any?] {
        [
            "id": id, "kind": kind.rawValue, "title": title, "notes": notes, "category": category.rawValue,
            "start": start, "end": end, "participants": participants.map(\.uuidString).sorted().joined(separator: ","),
            "parentID": parentID, "linkedID": linkedID, "identity": identity, "recurrence": recurrence.rawValue,
            "repeatUntil": repeatUntil, "originalDate": originalDate, "reminderMinutes": reminderMinutes,
            "metric": metric.rawValue, "target": target, "duration": duration, "amount": amount, "url": url,
            "completed": completed, "removed": deleted, "updatedAt": updatedAt
        ]
    }
    func write(to object: NSManagedObject, previous: RhythmRecord?) {
        let values = fields
        let baseline = previous?.fields
        // Assign only changed attributes. Core Data can merge edits to different fields.
        for (key, value) in values {
            if key != "updatedAt", let baseline, ((baseline[key] ?? nil) as? NSObject) == (value as? NSObject) { continue }
            let old = object.value(forKey: key) as? NSObject
            let new = value as? NSObject
            if old != new { object.setValue(value, forKey: key) }
        }
    }
}

@MainActor
final class Persistence: ObservableObject {
    let container: NSPersistentCloudKitContainer
    @Published var loaded = false
    @Published var status = "Abrindo seus dados…"
    @Published var error: String?
    let demo: Bool
    var privateStore: NSPersistentStore?
    var sharedStore: NSPersistentStore?
    private var observers: [NSObjectProtocol] = []
    var context: NSManagedObjectContext { container.viewContext }

    init(demo: Bool) {
        self.demo = demo
        container = NSPersistentCloudKitContainer(name: "NossoRitmo", managedObjectModel: RhythmModel.make())
        let directory = NSPersistentContainer.defaultDirectoryURL()
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { self.error = error.localizedDescription }
        func description(_ name: String, scope: CKDatabase.Scope?) -> NSPersistentStoreDescription {
            let value = NSPersistentStoreDescription(url: directory.appendingPathComponent(name))
            value.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            value.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            if let scope {
                let options = NSPersistentCloudKitContainerOptions(containerIdentifier: AppConfig.cloudID)
                options.databaseScope = scope; value.cloudKitContainerOptions = options
            }
            return value
        }
        container.persistentStoreDescriptions = demo ? [description("Demo.sqlite", scope: nil)] : [
            description("Private.sqlite", scope: .private), description("Shared.sqlite", scope: .shared)
        ]
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.loadPersistentStores { [weak self] description, failure in
            Task { @MainActor in
                guard let self else { return }
                if let failure { self.error = failure.localizedDescription; self.status = "Não foi possível abrir o armazenamento"; return }
                let store = self.container.persistentStoreCoordinator.persistentStores.first { $0.url == description.url }
                if description.cloudKitContainerOptions?.databaseScope == .shared { self.sharedStore = store }
                else { self.privateStore = store }
                let expected = self.demo ? 1 : 2
                if self.container.persistentStoreCoordinator.persistentStores.count == expected {
                    self.loaded = true; self.status = self.demo ? "Demonstração local" : "Dados locais prontos · iCloud em segundo plano"
                }
            }
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: container, queue: .main) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else { return }
            Task { @MainActor in
                guard let self else { return }
                if let failure = event.error { self.error = failure.localizedDescription; self.status = "Sincronização pendente · tente novamente" }
                else { self.status = event.endDate == nil ? "Sincronizando com o iCloud…" : "Sincronizado com o iCloud" }
            }
        })
    }

    func roots() throws -> [NSManagedObject] {
        try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "Space"))
    }
    func save() throws { if context.hasChanges { try context.save() } }
    func accept(_ metadata: CKShare.Metadata) async throws {
        guard let store = sharedStore else { throw RhythmError.message("Aguarde o armazenamento abrir e tente aceitar o convite novamente.") }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.acceptShareInvitations(from: [metadata], into: store) { _, failure in
                if let failure { continuation.resume(throwing: failure) } else { continuation.resume() }
            }
        }
    }
    func share(root: NSManagedObject) async throws -> CKShare {
        if let existing = try container.fetchShares(matching: [root.objectID])[root.objectID] { return existing }
        return try await withCheckedThrowingContinuation { continuation in
            container.share([root], to: nil) { _, share, _, failure in
                if let failure { continuation.resume(throwing: failure) }
                else if let share { continuation.resume(returning: share) }
                else { continuation.resume(throwing: RhythmError.message("O iCloud não retornou o convite.")) }
            }
        }
    }
    func invite(root: NSManagedObject, email: String) async throws -> URL {
        guard root.objectID.persistentStore == privateStore, let store = privateStore else {
            throw RhythmError.message("Somente quem criou o espaço pode convidar a segunda pessoa.")
        }
        let cloud = CKContainer(identifier: AppConfig.cloudID)
        let initial = try await share(root: root)
        let value = (try await cloud.privateCloudDatabase.record(for: initial.recordID)) as? CKShare ?? initial
        let participant: CKShare.Participant = try await withCheckedThrowingContinuation { continuation in
            cloud.fetchShareParticipant(withEmailAddress: email) { participant, error in
                if let error { continuation.resume(throwing: error) }
                else if let participant { continuation.resume(returning: participant) }
                else { continuation.resume(throwing: RhythmError.message("Conta iCloud não encontrada para esse e-mail.")) }
            }
        }
        guard participant.userIdentity.userRecordID != value.owner.userIdentity.userRecordID else {
            throw RhythmError.message("Informe o e-mail iCloud da outra pessoa.")
        }
        let guests = value.participants.filter { $0.role != .owner }
        if let existing = guests.first, existing.userIdentity.userRecordID != participant.userIdentity.userRecordID {
            throw RhythmError.message("O espaço já tem um convite ou participante. São permitidas apenas duas pessoas.")
        }
        guard guests.count <= 1 else { throw RhythmError.message("Este compartilhamento excede o limite de duas pessoas.") }
        value.publicPermission = .none
        value[CKShare.SystemFieldKey.title] = "Nosso Ritmo" as CKRecordValue
        if guests.isEmpty { participant.permission = .readWrite; value.addParticipant(participant) }
        let saved = try await cloud.privateCloudDatabase.save(value)
        guard let updated = saved as? CKShare, let url = updated.url else { throw RhythmError.message("Não foi possível criar o link privado.") }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.persistUpdatedShare(updated, in: store) { _, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
        return url
    }
    func leave(root: NSManagedObject) async throws {
        guard let store = root.objectID.persistentStore,
              let share = try container.fetchShares(matching: [root.objectID])[root.objectID] else {
            throw RhythmError.message("Não há compartilhamento ativo para encerrar.")
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.purgeObjectsAndRecordsInZone(with: share.recordID.zoneID, in: store) { _, failure in
                if let failure { continuation.resume(throwing: failure) } else { continuation.resume() }
            }
        }
    }
}

enum RhythmError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(value) = self { return value }; return nil }
}
