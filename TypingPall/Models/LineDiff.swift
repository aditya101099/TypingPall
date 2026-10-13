import Foundation

public enum DiffTolerance: String, Sendable, CaseIterable, Hashable {
    /// Strict character-for-character matching (after NFC normalization and leading indent strip).
    case strictCharacter
    /// Collapses redundant horizontal spaces around punctuation/operators while preserving string literals.
    case syntaxAwareTrivia
}

public struct DiffResult: Sendable, Equatable {
    /// Number of valid prefix characters matched in the target line.
    public let matchedTargetCharacters: Int
    /// Exact UTF-16 NSRange in the user's `typed` string where the mismatch begins (for TextKit 2 attributes).
    public let errorUTF16Range: NSRange?
    /// True when the user's input satisfies the entire target line.
    public let isComplete: Bool

    public init(matchedTargetCharacters: Int, errorUTF16Range: NSRange?, isComplete: Bool) {
        self.matchedTargetCharacters = matchedTargetCharacters
        self.errorUTF16Range = errorUTF16Range
        self.isComplete = isComplete
    }
}

/// Pre-computed representation of the target line, initialized ONCE per line advance.
public struct PreparedTargetLine: Sendable, Equatable {
    public let rawLine: String
    public let semanticTarget: String
    public let leadingIndentUTF16Count: Int

    public init(rawLine: String) {
        self.rawLine = rawLine
        // Strip leading indentation, normalized to NFC
        let trimmedStart = rawLine.drop(while: { $0 == " " || $0 == "\t" })
        self.leadingIndentUTF16Count = rawLine.utf16.count - trimmedStart.utf16.count
        self.semanticTarget = String(trimmedStart).precomposedStringWithCanonicalMapping
    }
}

public struct LineDiff: Equatable, Sendable {
    public let typed: String
    public let target: String
    /// Character offset in `typed`; nil while `typed` is a correct prefix of `target`.
    public let firstMismatch: Int?

    public init(typed: String, target: String) {
        self.typed = typed
        self.target = target
        var expected = target.makeIterator(), offset = 0, mismatch: Int?
        for character in typed {
            guard character == expected.next() else { mismatch = offset; break }
            offset += 1
        }
        firstMismatch = mismatch
    }

    public var isMatch: Bool { typed == target }
    /// UTF-16 range from the first mismatch to the end of `typed`, for text-view styling.
    public var mismatchRange: NSRange? {
        guard let firstMismatch else { return nil }
        let location = typed.prefix(firstMismatch).utf16.count
        return NSRange(location: location, length: typed.utf16.count - location)
    }
    /// The target character at the first mismatch, or the next one to type.
    public var expected: Character? {
        let offset = firstMismatch ?? typed.count
        guard offset < target.count else { return nil }
        return target[target.index(target.startIndex, offsetBy: offset)]
    }

    // MARK: - Fast Evaluator & Trivia Normalizer

    public static func evaluate(
        target: PreparedTargetLine,
        typed: String,
        tolerance: DiffTolerance = .strictCharacter
    ) -> DiffResult {
        let normalizedTyped = typed.precomposedStringWithCanonicalMapping

        if normalizedTyped.isEmpty {
            return DiffResult(
                matchedTargetCharacters: 0,
                errorUTF16Range: nil,
                isComplete: target.semanticTarget.isEmpty
            )
        }

        let expectedStr: String
        let effectiveTyped: String

        switch tolerance {
        case .strictCharacter:
            expectedStr = target.semanticTarget
            effectiveTyped = normalizedTyped
        case .syntaxAwareTrivia:
            expectedStr = normalizeCodeTrivia(target.semanticTarget)
            effectiveTyped = normalizeCodeTrivia(normalizedTyped)
        }

        // Fast path for exact match
        if effectiveTyped == expectedStr {
            return DiffResult(
                matchedTargetCharacters: target.semanticTarget.count,
                errorUTF16Range: nil,
                isComplete: true
            )
        }

        // Single-pass simultaneous traversal tracking exact UTF-16 offsets in the original `typed` string
        var expIter = expectedStr.makeIterator()
        var typedIdx = typed.startIndex
        var matchedCount = 0

        while typedIdx < typed.endIndex {
            let rawTypedChar = typed[typedIdx]
            let typedChar: Character = rawTypedChar.isASCII
                ? rawTypedChar
                : String(rawTypedChar).precomposedStringWithCanonicalMapping.first ?? rawTypedChar

            guard let expChar = expIter.next() else {
                let mismatchRange = NSRange(typedIdx..<typed.endIndex, in: typed)
                return DiffResult(
                    matchedTargetCharacters: matchedCount,
                    errorUTF16Range: mismatchRange,
                    isComplete: false
                )
            }

            if typedChar != expChar {
                if tolerance == .syntaxAwareTrivia && effectiveTyped == expectedStr {
                    return DiffResult(
                        matchedTargetCharacters: expectedStr.count,
                        errorUTF16Range: nil,
                        isComplete: true
                    )
                }
                let mismatchRange = NSRange(typedIdx..<typed.endIndex, in: typed)
                return DiffResult(
                    matchedTargetCharacters: matchedCount,
                    errorUTF16Range: mismatchRange,
                    isComplete: false
                )
            }

            matchedCount += 1
            typed.formIndex(after: &typedIdx)
        }

        let isComplete = (expIter.next() == nil)
        return DiffResult(
            matchedTargetCharacters: matchedCount,
            errorUTF16Range: nil,
            isComplete: isComplete
        )
    }

    /// Lightweight lexical normalizer: preserves exact spacing inside string literals,
    /// requires 1 space between adjacent identifiers (`int a`), and strips optional spaces around operators (`a=1` == `a = 1`).
    public static func normalizeCodeTrivia(_ input: String) -> String {
        var result = String()
        result.reserveCapacity(input.utf8.count)

        var inSingleQuote = false
        var inDoubleQuote = false
        var isEscaped = false
        var pendingSpace = false
        var lastSignificantChar: Character?

        for ch in input {
            if isEscaped {
                result.append(ch)
                isEscaped = false
                continue
            }
            if ch == "\\" && (inSingleQuote || inDoubleQuote) {
                result.append(ch)
                isEscaped = true
                continue
            }
            if ch == "\"" && !inSingleQuote {
                pendingSpace = false
                inDoubleQuote.toggle()
                result.append(ch)
                lastSignificantChar = ch
                continue
            }
            if ch == "'" && !inDoubleQuote {
                pendingSpace = false
                inSingleQuote.toggle()
                result.append(ch)
                lastSignificantChar = ch
                continue
            }

            if inSingleQuote || inDoubleQuote {
                result.append(ch)
                continue
            }

            // Outside string literals: collapse horizontal whitespace
            if ch == " " || ch == "\t" {
                pendingSpace = true
                continue
            }

            if pendingSpace {
                if let prev = lastSignificantChar, isIdentifierChar(prev) && isIdentifierChar(ch) {
                    result.append(" ")
                }
                pendingSpace = false
            }

            result.append(ch)
            lastSignificantChar = ch
        }
        return result
    }

    @inline(__always)
    private static func isIdentifierChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_" || c == "$"
    }
}
