import Foundation
import Testing
@testable import TypingPall

@Suite("DrillPhase State Machine & PracticeAction Reducer")
@MainActor
struct DrillStateMachineTests {

    @Test("Initial phase starts in .typing mode with zero progress")
    func initialPhaseStartsInTypingMode() {
        let vm = TypingScreenViewModel()
        guard case let .typing(subMode, currentLineIndex, lineProgress) = vm.phase else {
            Issue.record("Expected initial phase to be .typing, got \(vm.phase)")
            return
        }

        #expect(subMode == .copy)
        #expect(currentLineIndex == 0)
        #expect(lineProgress.matchedCount == 0)
        #expect(lineProgress.errorUTF16Range == nil)
        #expect(lineProgress.isLineComplete == false)
    }

    @Test("editorProgressChanged action updates lineProgress immutably")
    func editorProgressChangedUpdatesLineProgress() {
        let vm = TypingScreenViewModel()
        let errorRange = NSRange(location: 5, length: 2)

        vm.send(.editorProgressChanged(matchedCount: 5, errorRange: errorRange, isComplete: false))

        guard case let .typing(subMode, currentLineIndex, lineProgress) = vm.phase else {
            Issue.record("Expected .typing phase, got \(vm.phase)")
            return
        }

        #expect(subMode == .copy)
        #expect(currentLineIndex == 0)
        #expect(lineProgress.matchedCount == 5)
        #expect(lineProgress.errorUTF16Range == errorRange)
        #expect(lineProgress.isLineComplete == false)
    }

    @Test("selectSubMode action transitions drill sub-mode")
    func selectSubModeTransitionsMode() {
        let vm = TypingScreenViewModel()

        vm.send(.selectSubMode(.recall))
        guard case let .typing(subMode, _, _) = vm.phase else {
            Issue.record("Expected .typing phase, got \(vm.phase)")
            return
        }
        #expect(subMode == .recall)
        #expect(vm.mode == .recall)

        vm.send(.selectSubMode(.keyLines))
        guard case let .typing(subMode2, _, _) = vm.phase else {
            Issue.record("Expected .typing phase, got \(vm.phase)")
            return
        }
        #expect(subMode2 == .keyLines)
        #expect(vm.mode == .keyLines)
    }

    @Test("commitLineOnReturn in recall reveals hint on first attempt without line advance")
    func recallReturnRevealsHintFirst() {
        let vm = TypingScreenViewModel()
        vm.send(.selectSubMode(.recall))

        let initialPosition = vm.practicePosition
        vm.send(.commitLineOnReturn)

        // Position does not advance
        #expect(vm.practicePosition == initialPosition)
        #expect(vm.revealedLength > 0)
    }

    @Test("Advancing line increments bufferResetToken")
    func advanceLineIncrementsResetToken() {
        let vm = TypingScreenViewModel()
        let initialToken = vm.bufferResetToken

        vm.editorText = vm.currentLine
        vm.send(.commitLineOnReturn)

        #expect(vm.bufferResetToken == initialToken + 1)
        #expect(vm.practicePosition == 1)
    }

    @Test("restartLesson resets token and returns to start")
    func restartLessonResetsState() {
        let vm = TypingScreenViewModel()
        vm.editorText = vm.currentLine
        vm.advanceLine()

        let tokenBefore = vm.bufferResetToken
        vm.send(.restartLesson)

        #expect(vm.bufferResetToken == tokenBefore + 1)
        #expect(vm.practicePosition == 0)
        guard case let .typing(subMode, lineIndex, _) = vm.phase else {
            Issue.record("Expected .typing phase")
            return
        }
        #expect(subMode == .copy)
        #expect(lineIndex == 0)
    }

    @Test("Completed session transitions to .completed phase and accepts rating")
    func completedSessionAcceptsRating() {
        let vm = TypingScreenViewModel()
        vm.setMode(.recall)

        // Advance through all lines
        while !vm.isComplete {
            vm.editorText = vm.currentLine
            vm.advanceLine()
        }

        #expect(vm.isComplete == true)
        guard case let .completed(report) = vm.phase else {
            Issue.record("Expected .completed phase, got \(vm.phase)")
            return
        }
        #expect(report.totalLines == vm.practiceLines.count)
        #expect(report.selfRating == nil)

        vm.send(.rateSession(3))
        guard case let .completed(ratedReport) = vm.phase else {
            Issue.record("Expected .completed phase after rating")
            return
        }
        #expect(ratedReport.selfRating == 3)
    }
}
