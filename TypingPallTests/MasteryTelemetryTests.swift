import Foundation
import Testing
@testable import TypingPall

@Suite("Mastery Telemetry & Spaced Repetition Engine")
@MainActor
struct MasteryTelemetryTests {

    @Test("MasteryLevel ordering and ranking")
    func masteryLevelRanking() {
        #expect(MasteryLevel.unstarted < MasteryLevel.familiar)
        #expect(MasteryLevel.familiar < MasteryLevel.structural)
        #expect(MasteryLevel.structural < MasteryLevel.internalized)
        #expect(MasteryLevel.unstarted.rank == 0)
        #expect(MasteryLevel.internalized.rank == 3)
    }

    @Test("Copy mode with >= 85% clean lines promotes to .familiar")
    func copyModePromotesToFamiliar() {
        let record = RecallDecayScheduler.evaluate(
            patternID: "test-pattern",
            currentRecord: nil,
            mode: .copy,
            cleanLinesCount: 9,
            totalLinesCount: 10,
            hintsUsed: 0
        )

        #expect(record.level == .familiar)
        #expect(record.cleanLineRatio >= 0.85)
        #expect(record.nextReviewDate != nil)
    }

    @Test("Key Lines mode with <= 1 hint promotes to .structural")
    func keyLinesPromotesToStructural() {
        let familiarRecord = MasteryRecord(patternID: "test-pattern", level: .familiar)

        let record = RecallDecayScheduler.evaluate(
            patternID: "test-pattern",
            currentRecord: familiarRecord,
            mode: .keyLines,
            cleanLinesCount: 8,
            totalLinesCount: 10,
            hintsUsed: 1
        )

        #expect(record.level == .structural)
    }

    @Test("Recall mode with >= 90% clean lines and zero hints promotes to .internalized")
    func recallPromotesToInternalized() {
        let structuralRecord = MasteryRecord(patternID: "test-pattern", level: .structural)

        let record = RecallDecayScheduler.evaluate(
            patternID: "test-pattern",
            currentRecord: structuralRecord,
            mode: .recall,
            cleanLinesCount: 10,
            totalLinesCount: 10,
            hintsUsed: 0,
            selfRating: .effortless
        )

        #expect(record.level == .internalized)
        #expect(record.consecutiveCleanSessions == 1)
        #expect(record.stability > 2.0)
    }

    @Test("Forgot rating reduces stability and sets review interval to 1 day")
    func forgotRatingReducesStability() {
        let priorRecord = MasteryRecord(patternID: "test-pattern", level: .familiar, stability: 10.0)

        let evaluated = RecallDecayScheduler.evaluate(
            patternID: "test-pattern",
            currentRecord: priorRecord,
            mode: .recall,
            cleanLinesCount: 3,
            totalLinesCount: 10,
            hintsUsed: 3,
            selfRating: .forgot
        )

        #expect(evaluated.stability < priorRecord.stability)
        #expect(evaluated.difficulty > priorRecord.difficulty)
    }

    @Test("Pattern past review date is due for recall")
    func dueForRecallCalculation() {
        let yesterday = Date().addingTimeInterval(-86400)
        let record = MasteryRecord(
            patternID: "test-due",
            level: .internalized,
            nextReviewDate: yesterday
        )

        #expect(record.isDueForRecall == true)
        #expect(record.isFadingGold == true)

        let tomorrow = Date().addingTimeInterval(86400)
        let freshRecord = MasteryRecord(
            patternID: "test-fresh",
            level: .internalized,
            nextReviewDate: tomorrow
        )

        #expect(freshRecord.isDueForRecall == false)
        #expect(freshRecord.isFadingGold == false)
    }

    @Test("MasteryStore tracks and aggregates due counts")
    func masteryStoreOperations() {
        let defaults = UserDefaults(suiteName: "MasteryStoreTests-\(UUID().uuidString)")!
        let store = MasteryStore(defaults: defaults)

        let dueRecord = MasteryRecord(patternID: "due-1", level: .familiar, nextReviewDate: Date().addingTimeInterval(-3600))
        let futureRecord = MasteryRecord(patternID: "future-1", level: .structural, nextReviewDate: Date().addingTimeInterval(86400))

        store.update(record: dueRecord)
        store.update(record: futureRecord)

        #expect(store.level(for: "due-1") == .familiar)
        #expect(store.isDueForRecall(patternID: "due-1") == true)
        #expect(store.isDueForRecall(patternID: "future-1") == false)
        #expect(store.dueForRecallCount == 1)
        #expect(store.dueForRecallPatternIDs().contains("due-1"))
    }
}
