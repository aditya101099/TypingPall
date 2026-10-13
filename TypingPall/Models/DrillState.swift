import Foundation

// MARK: - Domain State Definitions

public enum PracticeSubMode: String, Sendable, CaseIterable {
    case copy       // Live reference visible, immediate error highlighting
    case keyLines   // Reference partially masked
    case recall     // Reference hidden until Return is pressed
}

public struct LineProgress: Sendable, Equatable {
    public var matchedCount: Int
    public var errorUTF16Range: NSRange?
    public var isLineComplete: Bool
    public var isRevealedByReturn: Bool

    public init(
        matchedCount: Int = 0,
        errorUTF16Range: NSRange? = nil,
        isLineComplete: Bool = false,
        isRevealedByReturn: Bool = false
    ) {
        self.matchedCount = matchedCount
        self.errorUTF16Range = errorUTF16Range
        self.isLineComplete = isLineComplete
        self.isRevealedByReturn = isRevealedByReturn
    }
}

public struct BugHuntState: Sendable, Equatable {
    public let plantedLineIndex: Int
    public var selectedLineIndex: Int?
    public var attemptsRemaining: Int
    public var isResolved: Bool

    public init(
        plantedLineIndex: Int,
        selectedLineIndex: Int? = nil,
        attemptsRemaining: Int = 3,
        isResolved: Bool = false
    ) {
        self.plantedLineIndex = plantedLineIndex
        self.selectedLineIndex = selectedLineIndex
        self.attemptsRemaining = attemptsRemaining
        self.isResolved = isResolved
    }
}

public struct ContrastState: Sendable, Equatable {
    public let variantALines: [String]
    public let variantBLines: [String]
    public var currentDiffIndex: Int

    public init(
        variantALines: [String],
        variantBLines: [String],
        currentDiffIndex: Int = 0
    ) {
        self.variantALines = variantALines
        self.variantBLines = variantBLines
        self.currentDiffIndex = currentDiffIndex
    }
}

public struct RecognitionState: Sendable, Equatable {
    public let promptScenario: String
    public let options: [String]
    public let correctIndex: Int
    public var selectedOption: Int?

    public init(
        promptScenario: String,
        options: [String],
        correctIndex: Int,
        selectedOption: Int? = nil
    ) {
        self.promptScenario = promptScenario
        self.options = options
        self.correctIndex = correctIndex
        self.selectedOption = selectedOption
    }
}

public struct SessionReport: Sendable, Equatable {
    public let totalLines: Int
    public let cleanLines: Int
    public let durationSeconds: TimeInterval
    public var selfRating: Int?

    public init(
        totalLines: Int,
        cleanLines: Int,
        durationSeconds: TimeInterval,
        selfRating: Int? = nil
    ) {
        self.totalLines = totalLines
        self.cleanLines = cleanLines
        self.durationSeconds = durationSeconds
        self.selfRating = selfRating
    }
}

public enum DrillPhase: Sendable, Equatable {
    case typing(subMode: PracticeSubMode, currentLineIndex: Int, lineProgress: LineProgress)
    case bugHunt(BugHuntState)
    case contrast(ContrastState)
    case recognition(RecognitionState)
    case completed(SessionReport)
}

// MARK: - Unidirectional Actions

public enum PracticeAction: Sendable {
    case editorProgressChanged(matchedCount: Int, errorRange: NSRange?, isComplete: Bool)
    case commitLineOnReturn
    case selectSubMode(PracticeSubMode)
    case selectBugLine(Int)
    case rateSession(Int)
    case restartLesson
}
