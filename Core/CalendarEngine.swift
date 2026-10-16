import Foundation

public enum CalendarEngine {
    public static func calendar(timeZone: TimeZone = .current) -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "pt_BR"); value.timeZone = timeZone
        value.firstWeekday = 2; value.minimumDaysInFirstWeek = 4
        return value
    }

    public static func occurrences(records: [RhythmRecord], in interval: DateInterval, calendar: Calendar) -> [Occurrence] {
        let exceptions = records.filter { $0.kind == .exception && !$0.deleted }
        var result: [Occurrence] = []
        for event in records where event.kind == .event && !event.deleted {
            var date = event.start
            let duration = event.end.timeIntervalSince(event.start)
            let component: Calendar.Component = event.recurrence == .weekly ? .weekOfYear : .day
            // Seek directly near the requested interval, then expand by calendar units to preserve local time across DST.
            if event.recurrence != .never && date < interval.start {
                let days = calendar.dateComponents([.day], from: date, to: interval.start).day ?? 0
                let skip = max(0, (event.recurrence == .weekly ? days / 7 : days) - Int(ceil(max(0, duration) / 86400)) - 1)
                date = calendar.date(byAdding: component, value: skip, to: date) ?? date
            }
            while date < interval.end {
                if let until = event.repeatUntil, date >= until { break }
                let exception = exceptions.first { $0.parentID == event.id && $0.originalDate == date }
                if exception == nil {
                    let end = date.addingTimeInterval(duration)
                    if end > interval.start { result.append(Occurrence(record: event, originalStart: date, start: date, end: end)) }
                }
                if event.recurrence == .never { break }
                guard let next = calendar.date(byAdding: component, value: 1, to: date), next > date else { break }
                date = next
            }
            // A moved occurrence may enter the interval even when its original date is outside it.
            for exception in exceptions where exception.parentID == event.id && !exception.completed {
                guard exception.start < interval.end, exception.end > interval.start,
                      let original = exception.originalDate else { continue }
                var replacement = event
                replacement.title = exception.title; replacement.notes = exception.notes
                replacement.category = exception.category; replacement.participants = exception.participants
                replacement.reminderMinutes = exception.reminderMinutes
                result.append(Occurrence(record: replacement, originalStart: original, start: exception.start, end: exception.end))
            }
        }
        return result.sorted { $0.start < $1.start }
    }

    public static func exception(for occurrence: Occurrence, edited: RhythmRecord?, existingID: UUID? = nil) -> RhythmRecord {
        var value = edited ?? occurrence.record
        value.id = existingID ?? UUID(); value.kind = .exception
        value.parentID = occurrence.record.id; value.originalDate = occurrence.originalStart
        value.completed = edited == nil // cancelled occurrence
        value.recurrence = .never
        return value
    }
}

public enum GoalEngine {
    public static func progress(goal: RhythmRecord, records: [RhythmRecord], now: Date, calendar: Calendar) -> Double {
        if goal.metric == .deadline { return goal.completed ? 1 : 0 }
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        let sessions = records.filter {
            $0.kind == .session && $0.completed && !$0.deleted && $0.category == goal.category &&
            (goal.participants.isEmpty ? Set($0.participants).count >= 2 : Set(goal.participants).isSubset(of: Set($0.participants)))
        }
        // Dedupe stable IDs: joint sessions count once, independent of participant count.
        let unique = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { a, b in a.updatedAt > b.updatedAt ? a : b }).values
        if goal.metric == .frequency { return Double(unique.filter { week.contains($0.start) && $0.start < week.end }.count) }
        let seconds = unique.reduce(0.0) { total, session in
            let wall = session.end.timeIntervalSince(session.start)
            guard wall > 0 else { return total }
            let overlap = max(0, min(session.end, week.end).timeIntervalSince(max(session.start, week.start)))
            // Distribute active duration proportionally when a paused session crosses a week boundary.
            return total + min(session.duration, wall) * overlap / wall
        }
        return seconds / 3600
    }
}
