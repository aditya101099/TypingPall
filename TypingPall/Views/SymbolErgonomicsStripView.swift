import SwiftUI

public struct SymbolErgonomicsStripView: View {
    public let targetLine: String
    public let typedText: String

    public init(targetLine: String, typedText: String = "") {
        self.targetLine = targetLine
        self.typedText = typedText
    }

    public struct SymbolChord: Equatable {
        public let symbol: String
        public let guide: String
        public let finger: String
        public let icon: String
    }

    public var upcomingChord: SymbolChord? {
        let remaining: String
        if targetLine.hasPrefix(typedText) {
            remaining = String(targetLine.dropFirst(typedText.count))
        } else {
            remaining = targetLine
        }

        // Ordered by length descending so multi-char tokens match first
        let patterns: [(token: String, guide: String, finger: String, icon: String)] = [
            ("->", "Dash then Shift + Greater-than", "Right Pinky → Right Ring", "arrow.right"),
            ("=>", "Equals then Shift + Greater-than", "Right Pinky → Right Ring", "arrow.right"),
            ("::", "Double Colon with Shift", "Shift + Right Pinky", "coloncurrencysign.circle"),
            ("!=", "Exclamation then Equals", "Shift + Left Pinky → Right Pinky", "equal"),
            ("==", "Double Equals chord", "Right Pinky twice", "equal"),
            ("<=", "Less-than then Equals", "Shift + Right Ring → Right Pinky", "lessthan"),
            (">=", "Greater-than then Equals", "Shift + Right Ring → Right Pinky", "greaterthan"),
            ("&&", "Double Ampersand chord", "Shift + Right Index twice", "number"),
            ("||", "Double Pipe with Shift", "Shift + Right Pinky twice", "line.diagonal"),
            ("??", "Double Question with Shift", "Shift + Right Pinky twice", "questionmark"),
            ("+=", "Plus then Equals", "Shift + Right Pinky → Right Pinky", "plus"),
            ("-=", "Minus then Equals", "Right Pinky twice", "minus"),
            ("*=", "Asterisk then Equals", "Shift + Right Middle → Right Pinky", "asterisk"),
            ("/=", "Slash then Equals", "Right Pinky twice", "divide"),
            ("{}", "Curly Braces chord", "Shift + Right Pinky", "curlybraces"),
            ("[]", "Square Brackets chord", "Right Pinky brackets", "square"),
            ("()", "Parentheses chord", "Shift + Right Middle/Ring", "oval"),
            (";", "Semicolon terminator", "Right Pinky home row", "character")
        ]

        for p in patterns {
            if remaining.contains(p.token) {
                return SymbolChord(symbol: p.token, guide: p.guide, finger: p.finger, icon: p.icon)
            }
        }
        return nil
    }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: upcomingChord?.icon ?? "keyboard")
                .foregroundColor(.secondary)
                .font(.system(size: 14, weight: .medium))

            if let chord = upcomingChord {
                HStack(spacing: 8) {
                    Text(chord.symbol)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.16))
                        .foregroundColor(Color.accentColor)
                        .cornerRadius(6)

                    Text(chord.guide)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)

                    Text("·")
                        .foregroundColor(.secondary)

                    Text(chord.finger)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Fluent Flow · Natural home-row cadence")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text("Symbol Ergonomics Strip")
                .font(.system(size: 10, weight: .semibold))
                .textCase(.uppercase)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(TypingPalette.activeLine.opacity(0.6))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(TypingPalette.subtleBorder, lineWidth: 1)
        )
    }
}
