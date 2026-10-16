import Foundation

public enum Category: String, CaseIterable, Codable, Identifiable {
    case couple, study, gym, outdoors, streaming
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .couple: return "A dois"
        case .study: return "Estudos"
        case .gym: return "Academia"
        case .outdoors: return "Ar livre"
        case .streaming: return "Streaming"
        }
    }
    public var symbol: String {
        switch self {
        case .couple: return "heart"
        case .study: return "book.closed"
        case .gym: return "dumbbell"
        case .outdoors: return "sun.max"
        case .streaming: return "play.tv"
        }
    }
}

public enum RecordKind: String, Codable, CaseIterable {
    case member, event, exception, goal, session, subject, workout, trip, itinerary, checklist, expense, music
}
public enum RepeatRule: String, Codable, CaseIterable {
    case never, daily, weekly
    public var title: String {
        switch self { case .never: return "Não repetir"; case .daily: return "Diariamente"; case .weekly: return "Semanalmente" }
    }
}
public enum GoalMetric: String, Codable, CaseIterable {
    case hours, frequency, deadline
    public var title: String {
        switch self { case .hours: return "Horas por semana"; case .frequency: return "Vezes por semana"; case .deadline: return "Concluir até uma data" }
    }
}

/// Each property is stored as a separate Core Data attribute (no opaque JSON payload).
public struct RhythmRecord: Identifiable, Codable, Equatable {
    public var id = UUID()
    public var kind: RecordKind
    public var title: String
    public var notes = ""
    public var category: Category = .couple
    public var start = Date()
    public var end = Date().addingTimeInterval(3600)
    public var participants: [UUID] = []
    public var parentID: UUID?
    public var linkedID: UUID?
    public var identity = ""
    public var recurrence: RepeatRule = .never
    public var repeatUntil: Date?
    public var originalDate: Date?
    public var reminderMinutes: Int = -1
    public var metric: GoalMetric = .hours
    public var target: Double = 1
    public var duration: TimeInterval = 0
    public var amount: Double = 0
    public var url = ""
    public var completed = false
    public var deleted = false
    public var updatedAt = Date()

    public init(kind: RecordKind, title: String) { self.kind = kind; self.title = title }
}

public struct Occurrence: Identifiable, Equatable {
    public var record: RhythmRecord
    public var originalStart: Date
    public var start: Date
    public var end: Date
    public var id: String { "\(record.id.uuidString)-\(originalStart.timeIntervalSince1970)" }
    public init(record: RhythmRecord, originalStart: Date, start: Date, end: Date) {
        self.record = record; self.originalStart = originalStart; self.start = start; self.end = end
    }
}

public struct ActiveTimer: Codable, Equatable {
    public var session: RhythmRecord
    public var accumulated: TimeInterval = 0
    public var runningSince: Date?
    public init(session: RhythmRecord, now: Date = Date()) { self.session = session; runningSince = now }
    public func elapsed(at now: Date) -> TimeInterval {
        accumulated + (runningSince.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }
    public mutating func pause(at now: Date) { accumulated = elapsed(at: now); runningSince = nil }
    public mutating func resume(at now: Date) { if runningSince == nil { runningSince = now } }
    public func finish(at now: Date) -> RhythmRecord {
        var result = session
        result.duration = elapsed(at: now); result.end = now; result.completed = true
        return result
    }
}

public enum RhythmValidation {
    public static func message(for item: RhythmRecord) -> String? {
        if item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Informe um título." }
        if [.event, .itinerary, .trip].contains(item.kind), item.end <= item.start { return "O término deve ser depois do início." }
        if item.kind == .goal, !item.target.isFinite || item.target <= 0 { return "A meta deve ser maior que zero." }
        if item.kind == .session, !item.duration.isFinite || item.duration <= 0 { return "Informe uma duração maior que zero." }
        if [.expense, .trip].contains(item.kind), !item.amount.isFinite || item.amount < 0 { return "Informe um valor válido." }
        if item.kind == .music, !isMusicURL(item.url) { return "Use um link HTTPS do Spotify, Apple Music ou YouTube." }
        return nil
    }
    public static func isMusicURL(_ value: String) -> Bool {
        guard let url = URL(string: value), url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return ["open.spotify.com", "music.apple.com", "youtube.com", "www.youtube.com", "music.youtube.com", "youtu.be"].contains(host)
    }
}
