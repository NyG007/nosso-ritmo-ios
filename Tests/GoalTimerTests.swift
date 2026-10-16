import XCTest
@testable import NossoRitmoCore

final class GoalTimerTests: XCTestCase {
    let a = UUID(), b = UUID()
    let now = ISO8601DateFormatter().date(from: "2026-10-15T15:00:00Z")!
    let cal = CalendarEngine.calendar(timeZone: TimeZone(identifier: "America/Sao_Paulo")!)
    func session(_ ids: [UUID]) -> RhythmRecord {
        var value = RhythmRecord(kind: .session, title: "Caminhada")
        value.category = .outdoors; value.start = now.addingTimeInterval(-3600); value.end = now
        value.duration = 3600; value.completed = true; value.participants = ids; return value
    }
    func goal(_ ids: [UUID]) -> RhythmRecord {
        var value = RhythmRecord(kind: .goal, title: "Ar livre")
        value.category = .outdoors; value.participants = ids; return value
    }
    func progress(_ goal: RhythmRecord, _ records: [RhythmRecord]) -> Double { GoalEngine.progress(goal: goal, records: records, now: now, calendar: cal) }
    func testJointCountsOnceForCoupleAndEachPerson() {
        let shared = session([a,b])
        for ids in [[a,b], [a], [b], []] { XCTAssertEqual(progress(goal(ids), [shared]), 1) }
    }
    func testIndividualActivityDoesNotCountForJointGoal() {
        XCTAssertEqual(progress(goal([a,b]), [session([a])]), 0)
        XCTAssertEqual(progress(goal([]), [session([a])]), 0)
    }
    func testPlannedUnfinishedAndDeletedDoNotCount() {
        var unfinished = session([a,b]); unfinished.completed = false
        var planned = session([a,b]); planned.kind = .event
        var removed = session([a,b]); removed.deleted = true
        XCTAssertEqual(progress(goal([]), [unfinished, planned, removed]), 0)
    }
    func testDuplicateIDCountsOnceAndCorrectionRecalculates() {
        let first = session([a,b]); var corrected = first; corrected.duration = 1800; corrected.updatedAt = first.updatedAt.addingTimeInterval(1)
        XCTAssertEqual(progress(goal([]), [first, corrected]), 0.5)
    }
    func testWeekBoundarySplitsHours() {
        var value = session([a,b]); value.start = cal.dateInterval(of: .weekOfYear, for: now)!.start.addingTimeInterval(-3600)
        value.end = value.start.addingTimeInterval(7200); value.duration = 7200
        XCTAssertEqual(progress(goal([]), [value]), 1)
    }
    func testFrequencyCountsSessionsNotHours() {
        var value = goal([a]); value.metric = .frequency
        XCTAssertEqual(progress(value, [session([a]), session([a,b])]), 2)
    }
    func testDeadlineUsesCompletion() {
        var value = goal([]); value.metric = .deadline
        XCTAssertEqual(progress(value, []), 0); value.completed = true; XCTAssertEqual(progress(value, []), 1)
    }
    func testTimerPauseResumeAndPersistence() throws {
        var timer = ActiveTimer(session: session([a,b]), now: now)
        timer.pause(at: now.addingTimeInterval(60))
        XCTAssertEqual(timer.elapsed(at: now.addingTimeInterval(600)), 60)
        timer = try JSONDecoder().decode(ActiveTimer.self, from: JSONEncoder().encode(timer))
        timer.resume(at: now.addingTimeInterval(600)); timer.resume(at: now.addingTimeInterval(650))
        let finished = timer.finish(at: now.addingTimeInterval(720))
        XCTAssertEqual(finished.duration, 180); XCTAssertTrue(finished.completed)
        XCTAssertEqual(finished.id, timer.session.id)
    }
    func testMusicURLValidation() {
        XCTAssertTrue(RhythmValidation.isMusicURL("https://open.spotify.com/track/abc"))
        XCTAssertTrue(RhythmValidation.isMusicURL("https://youtu.be/abc"))
        for url in ["http://youtube.com/a", "https://youtube.com.evil.test/a", "javascript:alert(1)", "not a url"] { XCTAssertFalse(RhythmValidation.isMusicURL(url)) }
    }
    func testInvalidDurationsAndEventDates() {
        var value = session([a]); value.duration = -1; XCTAssertNotNil(RhythmValidation.message(for: value))
        value.kind = .event; value.end = value.start; XCTAssertNotNil(RhythmValidation.message(for: value))
    }
}
