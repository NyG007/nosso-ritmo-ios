import XCTest
@testable import NossoRitmoCore

final class CalendarTests: XCTestCase {
    let cal = CalendarEngine.calendar(timeZone: TimeZone(identifier: "America/Sao_Paulo")!)
    func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    func event(_ date: Date, repeat rule: RepeatRule = .never) -> RhythmRecord {
        var item = RhythmRecord(kind: .event, title: "Juntos")
        item.start = date; item.end = date.addingTimeInterval(3600); item.recurrence = rule; return item
    }
    func testWeekStartsMonday() {
        let week = cal.dateInterval(of: .weekOfYear, for: date("2026-10-18T15:00:00Z"))!
        XCTAssertEqual(cal.component(.weekday, from: week.start), 2)
    }
    func testDailyExpansionAndExclusiveIntervalEnd() {
        let item = event(date("2026-10-12T15:00:00Z"), repeat: .daily)
        let range = DateInterval(start: item.start, end: item.start.addingTimeInterval(86400 * 3))
        XCTAssertEqual(CalendarEngine.occurrences(records: [item], in: range, calendar: cal).count, 3)
    }
    func testWeeklyExpansionAndCutoff() {
        var item = event(date("2026-10-12T15:00:00Z"), repeat: .weekly)
        item.repeatUntil = date("2026-10-26T15:00:00Z")
        let range = DateInterval(start: item.start, duration: 86400 * 30)
        XCTAssertEqual(CalendarEngine.occurrences(records: [item], in: range, calendar: cal).count, 2)
    }
    func testCancelOnlyOneOccurrence() {
        let item = event(date("2026-10-12T15:00:00Z"), repeat: .daily)
        let range = DateInterval(start: item.start, duration: 86400 * 3)
        let before = CalendarEngine.occurrences(records: [item], in: range, calendar: cal)
        let exception = CalendarEngine.exception(for: before[1], edited: nil)
        let after = CalendarEngine.occurrences(records: [item, exception], in: range, calendar: cal)
        XCTAssertEqual(after.count, 2); XCTAssertFalse(after.contains { $0.originalStart == before[1].start })
    }
    func testMovedOccurrenceEntersAnotherDayWithoutDuplicating() {
        let item = event(date("2026-10-12T15:00:00Z"), repeat: .weekly)
        let range = DateInterval(start: item.start, duration: 3600)
        let occurrence = CalendarEngine.occurrences(records: [item], in: range, calendar: cal)[0]
        var moved = item; moved.start = date("2026-10-14T18:00:00Z"); moved.end = moved.start.addingTimeInterval(3600)
        let exception = CalendarEngine.exception(for: occurrence, edited: moved)
        XCTAssertTrue(CalendarEngine.occurrences(records: [item, exception], in: range, calendar: cal).isEmpty)
        let otherDay = cal.dateInterval(of: .day, for: moved.start)!
        let actual = CalendarEngine.occurrences(records: [item, exception], in: otherDay, calendar: cal)
        XCTAssertEqual(actual.count, 1); XCTAssertEqual(actual[0].start, moved.start)
    }
    func testEventAcrossMidnightAppearsOnBothDays() {
        var item = event(date("2026-10-13T02:30:00Z")) // 23:30 local
        item.end = item.start.addingTimeInterval(7200)
        for offset in [0, 7200] {
            let day = cal.dateInterval(of: .day, for: item.start.addingTimeInterval(Double(offset)))!
            XCTAssertEqual(CalendarEngine.occurrences(records: [item], in: day, calendar: cal).count, 1)
        }
    }
    func testDSTKeepsLocalHour() {
        let calendar = CalendarEngine.calendar(timeZone: TimeZone(identifier: "America/New_York")!)
        let item = event(date("2026-03-07T15:00:00Z"), repeat: .daily)
        let occurrences = CalendarEngine.occurrences(records: [item], in: DateInterval(start: item.start, duration: 86400 * 3), calendar: calendar)
        XCTAssertTrue(occurrences.allSatisfy { calendar.component(.hour, from: $0.start) == 10 })
    }
    func testDeletedEventDoesNotAppear() {
        var item = event(date("2026-10-12T15:00:00Z")); item.deleted = true
        XCTAssertTrue(CalendarEngine.occurrences(records: [item], in: DateInterval(start: item.start, duration: 7200), calendar: cal).isEmpty)
    }
}
