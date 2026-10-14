import SwiftUI
import Foundation

// MARK: - 3-Tier Mastery Badges

public enum MasteryLevel: String, Codable, Sendable, Comparable {
    case unstarted
    case familiar      // Stage 1: Bronze (Copy mode >= 85% clean lines)
    case structural    // Stage 2: Silver (Key Lines mode <= 1 hint)
    case internalized  // Stage 3: Gold (Recall mode >= 90% clean lines)

    public var rank: Int {
        switch self {
        case .unstarted: return 0
        case .familiar: return 1
        case .structural: return 2
        case .internalized: return 3
        }
    }

    public static func < (lhs: MasteryLevel, rhs: MasteryLevel) -> Bool {
        lhs.rank < rhs.rank
    }

    public var color: Color {
        switch self {
        case .unstarted: return Color.secondary.opacity(0.3)
        case .familiar: return Color(red: 0.80, green: 0.50, blue: 0.20) // Bronze
        case .structural: return Color(red: 0.75, green: 0.78, blue: 0.82) // Silver
        case .internalized: return Color(red: 0.96, green: 0.77, blue: 0.20) // Gold
        }
    }

    public var title: String {
        switch self {
        case .unstarted: return "Unstarted"
        case .familiar: return "Familiar"
        case .structural: return "Structural"
        case .internalized: return "Internalized"
        }
    }
}

// MARK: - Pattern Mastery & Spaced Repetition Record

public struct MasteryRecord: Codable, Sendable, Equatable {
    public let patternID: String
    public var level: MasteryLevel
    public var cleanLineRatio: Double
    public var consecutiveCleanSessions: Int
    public var stability: Double     // estimated memory retention half-life in days
    public var difficulty: Double    // scale 1.0 (easiest) to 10.0 (hardest)
    public var lastReviewedAt: Date?
    public var nextReviewDate: Date?

    public init(patternID: String,
                level: MasteryLevel = .unstarted,
                cleanLineRatio: Double = 0.0,
                consecutiveCleanSessions: Int = 0,
                stability: Double = 1.0,
                difficulty: Double = 5.0,
                lastReviewedAt: Date? = nil,
                nextReviewDate: Date? = nil) {
        self.patternID = patternID
        self.level = level
        self.cleanLineRatio = cleanLineRatio
        self.consecutiveCleanSessions = consecutiveCleanSessions
        self.stability = max(0.5, stability)
        self.difficulty = min(10.0, max(1.0, difficulty))
        self.lastReviewedAt = lastReviewedAt
        self.nextReviewDate = nextReviewDate
    }

    public var isDueForRecall: Bool {
        guard let nextReviewDate else { return false }
        return nextReviewDate <= Date()
    }

    public var isFadingGold: Bool {
        level == .internalized && isDueForRecall
    }
}

// MARK: - FSRS-Lite Spaced Repetition Engine

enum RecallDecayScheduler {
    static func evaluate(
        patternID: String,
        currentRecord: MasteryRecord?,
        mode: PracticeMode,
        cleanLinesCount: Int,
        totalLinesCount: Int,
        hintsUsed: Int,
        selfRating: SelfRating? = nil,
        hesitationCount: Int = 0,
        now: Date = Date()
    ) -> MasteryRecord {
        let total = max(1, totalLinesCount)
        let cleanRatio = Double(cleanLinesCount) / Double(total)
        var record = currentRecord ?? MasteryRecord(patternID: patternID)

        // 1. Mastery Stage Advancement Check
        var newLevel = record.level
        switch mode {
        case .copy:
            if cleanRatio >= 0.85 && newLevel < .familiar {
                newLevel = .familiar
            }
        case .keyLines:
            if hintsUsed <= 1 && cleanRatio >= 0.70 && newLevel < .structural {
                newLevel = .structural
            }
        case .recall:
            if cleanRatio >= 0.90 && hintsUsed == 0 {
                newLevel = .internalized
            }
        }
        record.level = newLevel
        record.cleanLineRatio = cleanRatio

        // 2. FSRS-Lite Decay & Stability Interval Calculation
        let rating = selfRating ?? (cleanRatio >= 0.9 && hintsUsed == 0 ? .solid : (cleanRatio < 0.6 ? .forgot : .shaky))
        var currentStability = max(1.0, record.stability)
        var currentDifficulty = record.difficulty

        // Update difficulty based on rating
        switch rating {
        case .forgot:
            currentDifficulty = min(10.0, currentDifficulty + 0.8)
            currentStability = max(1.0, currentStability * 0.4)
            record.consecutiveCleanSessions = 0
        case .shaky:
            currentDifficulty = min(10.0, currentDifficulty + 0.3)
            currentStability = max(1.5, currentStability * 0.85)
            record.consecutiveCleanSessions = 0
        case .solid:
            currentDifficulty = max(1.0, currentDifficulty - 0.2)
            currentStability = currentStability * (1.8 + (10.0 - currentDifficulty) * 0.1)
            record.consecutiveCleanSessions += 1
        case .effortless:
            currentDifficulty = max(1.0, currentDifficulty - 0.5)
            currentStability = currentStability * (2.6 + (10.0 - currentDifficulty) * 0.15)
            record.consecutiveCleanSessions += 1
        }

        // Implicit Behavioral Penalties
        if hintsUsed > 0 {
            currentStability = max(1.0, currentStability * pow(0.75, Double(hintsUsed)))
        }
        if hesitationCount > 2 {
            currentStability = max(1.0, currentStability * 0.85)
        }

        // Interval in whole days (clamped between 1 and 180 days)
        let intervalDays = max(1, min(180, Int(currentStability.rounded())))
        let nextDate = Calendar.current.date(byAdding: .day, value: intervalDays, to: now) ?? now.addingTimeInterval(Double(intervalDays * 86400))

        record.stability = currentStability
        record.difficulty = currentDifficulty
        record.lastReviewedAt = now
        record.nextReviewDate = nextDate

        return record
    }
}

// MARK: - Reactive Mastery Store

@MainActor
public final class MasteryStore: ObservableObject {
    public static let shared = MasteryStore()

    private let defaults: UserDefaults
    private let storageKey = "mastery.records.v1"

    @Published public private(set) var records: [String: MasteryRecord] = [:]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadRecords()
    }

    public func record(for patternID: String) -> MasteryRecord {
        records[patternID] ?? MasteryRecord(patternID: patternID)
    }

    public func level(for patternID: String) -> MasteryLevel {
        records[patternID]?.level ?? .unstarted
    }

    public func isDueForRecall(patternID: String) -> Bool {
        records[patternID]?.isDueForRecall ?? false
    }

    public var dueForRecallCount: Int {
        records.values.filter(\.isDueForRecall).count
    }

    public func dueForRecallPatternIDs() -> Set<String> {
        Set(records.values.filter(\.isDueForRecall).map(\.patternID))
    }

    public func update(record: MasteryRecord) {
        records[record.patternID] = record
        persistRecords()
    }

    private func loadRecords() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: MasteryRecord].self, from: data) else {
            return
        }
        self.records = decoded
    }

    private func persistRecords() {
        if let encoded = try? JSONEncoder().encode(records) {
            defaults.set(encoded, forKey: storageKey)
        }
    }
}

// MARK: - Tri-Ring / 3-Segment Mastery Glyph

public struct TriRingMasteryGlyph: View {
    public let level: MasteryLevel
    public var isDueForRecall: Bool = false
    public var size: CGFloat = 16

    public init(level: MasteryLevel, isDueForRecall: Bool = false, size: CGFloat = 16) {
        self.level = level
        self.isDueForRecall = isDueForRecall
        self.size = size
    }

    public var body: some View {
        ZStack {
            // Background track (3 faint segments)
            Circle()
                .stroke(Color.secondary.opacity(0.18), lineWidth: size * 0.18)

            // Stage 1 (Bronze arc 0 -> 120 deg)
            if level >= .familiar {
                Circle()
                    .trim(from: 0.04, to: 0.30)
                    .stroke(MasteryLevel.familiar.color, style: StrokeStyle(lineWidth: size * 0.18, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }

            // Stage 2 (Silver arc 120 -> 240 deg)
            if level >= .structural {
                Circle()
                    .trim(from: 0.37, to: 0.63)
                    .stroke(MasteryLevel.structural.color, style: StrokeStyle(lineWidth: size * 0.18, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }

            // Stage 3 (Gold arc 240 -> 360 deg)
            if level >= .internalized {
                Circle()
                    .trim(from: 0.70, to: 0.96)
                    .stroke(MasteryLevel.internalized.color.opacity(isDueForRecall ? 0.45 : 1.0),
                            style: StrokeStyle(lineWidth: size * 0.18, lineCap: .round, dash: isDueForRecall ? [2, 2] : []))
                    .rotationEffect(.degrees(-90))
            }

            // Center pip for internalized
            if level == .internalized && !isDueForRecall {
                Circle()
                    .fill(MasteryLevel.internalized.color)
                    .frame(width: size * 0.32, height: size * 0.32)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(level.title) mastery\(isDueForRecall ? ", review due" : "")")
    }
}
