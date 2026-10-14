import SwiftUI
import AppKit

struct InterleavedCodeCanvasView: View {
    @ObservedObject var viewModel: TypingScreenViewModel
    let fontSize: Double
    var onSelectRow: ((Int) -> Void)? = nil

    @State private var hasSeenTip = false
    @State private var shakeLineOffset: CGFloat = 0

    init(viewModel: TypingScreenViewModel, fontSize: Double, onSelectRow: ((Int) -> Void)? = nil) {
        self.viewModel = viewModel
        self.fontSize = fontSize
        self.onSelectRow = onSelectRow
    }

    private var currentLineIndex: Int { viewModel.currentLineIndex }
    private var codeFontSize: Double { ReferenceCodeView.referenceFontSize(for: fontSize) }
    private var charWidth: CGFloat { CGFloat(codeFontSize * 0.602) }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.referenceRows) { row in
                        lineRow(for: row)
                            .id(row.sourceIndex)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
            }
            .background(TypingPalette.codeCanvas)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(TypingPalette.subtleBorder, lineWidth: 1)
            )
            .onChange(of: currentLineIndex) { newIndex in
                withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
            .onChange(of: viewModel.placeholderText) { _ in
                proxy.scrollTo(0, anchor: .top)
            }
        }
    }

    @ViewBuilder
    private func lineRow(for row: ReferenceRow) -> some View {
        if row.isCurrent && !viewModel.isComplete && viewModel.hasPracticeLines {
            activeAccordionRow(for: row)
                .transition(.opacity)
        } else {
            inactiveLineRow(for: row)
        }
    }

    // MARK: - Inactive Row (Static Context)

    private func inactiveLineRow(for row: ReferenceRow) -> some View {
        let split = ReferenceCodeView.split(row.text)
        let isClickableBugRow = onSelectRow != nil

        let content = HStack(alignment: .firstTextBaseline, spacing: 8) {
            // Line Number
            Text("\(row.sourceIndex + 1)")
                .font(.system(size: max(10, codeFontSize - 2), weight: .regular, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.7))
                .frame(width: 32, alignment: .trailing)

            // Gutter status dot / diagnostic heatmap bar
            gutterStatusView(for: row)
                .frame(width: 14)

            // Indentation + Code
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(split.indent)
                    .font(.system(size: codeFontSize, design: .monospaced))

                if row.isMasked {
                    Text(String(repeating: MaskedLine.hidden, count: split.code.count))
                        .foregroundColor(.secondary.opacity(0.4))
                        .font(.system(size: codeFontSize, design: .monospaced))
                } else if row.isSkipped || viewModel.language == .plainText {
                    Text(split.code.isEmpty ? " " : split.code)
                        .italic(row.isSkipped)
                        .foregroundColor(.secondary)
                        .font(.system(size: codeFontSize, design: .monospaced))
                } else {
                    let highlighted = CodeHighlighter.highlight(code: split.code.isEmpty ? " " : split.code, language: viewModel.language)
                    Text(highlighted)
                        .font(.system(size: codeFontSize, design: .monospaced))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .contentShape(Rectangle())

        return Group {
            if isClickableBugRow {
                Button {
                    onSelectRow?(row.sourceIndex)
                } label: {
                    content
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("referenceLine\(row.sourceIndex)")
            } else {
                content
            }
        }
    }

    // MARK: - Active Line Accordion Row (Unified Eye-Fixation Anchor)

    private func activeAccordionRow(for row: ReferenceRow) -> some View {
        let split = ReferenceCodeView.split(row.text)
        let indentColumns = split.indent.count
        let dynamicIndentPadding = max(16.0, CGFloat(indentColumns) * charWidth + 16.0)

        return VStack(alignment: .leading, spacing: 0) {
            // Header: Reference line (adapts based on mode)
            if shouldShowReferenceRow {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(row.sourceIndex + 1)")
                        .font(.system(size: max(10, codeFontSize - 2), weight: .bold, design: .monospaced))
                        .foregroundColor(Color.accentColor)
                        .frame(width: 32, alignment: .trailing)

                    Image(systemName: "arrowtriangle.right.fill")
                        .font(.system(size: 8))
                        .foregroundColor(Color.accentColor)
                        .frame(width: 14)

                    // Reference Target Line
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(split.indent)
                            .font(.system(size: codeFontSize, design: .monospaced))

                        if viewModel.mode == .keyLines && viewModel.revealedLength == 0 {
                            Text(String(repeating: MaskedLine.hidden, count: split.code.count))
                                .foregroundColor(TypingPalette.statusHinted)
                                .font(.system(size: codeFontSize, design: .monospaced))
                        } else if viewModel.mode == .recall && viewModel.revealedLength > 0 {
                            Text(viewModel.visibleTarget)
                                .foregroundColor(TypingPalette.statusHinted)
                                .font(.system(size: codeFontSize, design: .monospaced))
                        } else {
                            let highlighted = CodeHighlighter.highlight(code: split.code.isEmpty ? " " : split.code, language: viewModel.language)
                            Text(highlighted)
                                .font(.system(size: codeFontSize, design: .monospaced))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if viewModel.revealedLength > 0 {
                        Text("Hint revealed")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(TypingPalette.statusHinted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(TypingPalette.statusHinted.opacity(0.12))
                            .cornerRadius(4)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 6)
            }

            // TextKit 2 Input Row
            HStack(alignment: .center, spacing: 8) {
                TextKit2TypingViewWrapper(
                    targetLine: viewModel.currentLine,
                    resetToken: viewModel.bufferResetToken,
                    fontSize: CGFloat(codeFontSize),
                    diffTolerance: viewModel.diffTolerance,
                    indentPadding: dynamicIndentPadding,
                    isEnabled: viewModel.hasPracticeLines && !viewModel.isComplete,
                    onProgress: { result in
                        viewModel.send(.editorProgressChanged(
                            matchedCount: result.matchedTargetCharacters,
                            errorRange: result.errorUTF16Range,
                            isComplete: result.isComplete
                        ))
                    },
                    onReturn: {
                        if viewModel.isLineMatched || viewModel.mode.isGraded {
                            viewModel.send(.commitLineOnReturn)
                        } else {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                shakeLineOffset = -6
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                shakeLineOffset = 0
                            }
                        }
                    }
                )
                .frame(minHeight: 42, maxHeight: 48)

                // Inline Actions & Commit Indicator
                HStack(spacing: 8) {
                    if viewModel.isLineMatched {
                        HStack(spacing: 4) {
                            Text("↵")
                                .font(.system(size: 13, weight: .bold))
                            Text("Return")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(TypingPalette.lineMatchedBorder)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(TypingPalette.lineMatchedBorder.opacity(0.15))
                        .cornerRadius(6)
                        .transition(.scale.combined(with: .opacity))
                    }

                    Button {
                        viewModel.revealHint()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "lightbulb")
                                .font(.system(size: 11))
                            Text("⌘'")
                                .font(.system(size: 10, weight: .bold))
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(viewModel.isComplete)
                    .help("Reveal next token hint (⌘')")
                    .accessibilityIdentifier("hintButton")
                }
                .padding(.trailing, 12)
            }
            .padding(.bottom, 6)
        }
        .background(TypingPalette.activeLine)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(viewModel.isLineMatched ? TypingPalette.lineMatchedBorder : Color.accentColor.opacity(0.4),
                        lineWidth: viewModel.isLineMatched ? 1.5 : 1)
        )
        .offset(x: shakeLineOffset)
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }

    private var shouldShowReferenceRow: Bool {
        switch viewModel.mode {
        case .copy:
            return true
        case .keyLines:
            return true
        case .recall:
            return viewModel.revealedLength > 0
        }
    }

    // MARK: - Gutter Status & Diagnostic Heatmap

    @ViewBuilder
    private func gutterStatusView(for row: ReferenceRow) -> some View {
        if viewModel.isComplete {
            // Diagnostic X-Ray Heatmap on Completion
            let attempt = viewModel.lineAttempts[row.sourceIndex]
            if let att = attempt {
                let isClean = att.isClean
                let usedHint = att.hints > 0
                RoundedRectangle(cornerRadius: 2)
                    .fill(isClean ? TypingPalette.statusClean : (usedHint ? TypingPalette.statusHinted : TypingPalette.statusCorrected))
                    .frame(width: 4, height: 16)
                    .help("Line \(row.sourceIndex + 1): \(isClean ? "Clean first try" : usedHint ? "Hint used" : "Needed correction")")
            } else if row.isSkipped {
                Text("⤼")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.5))
            }
        } else {
            // Live Status Marker
            switch row.marker {
            case .neededSecondLook?:
                Circle()
                    .fill(TypingPalette.statusCorrected)
                    .frame(width: 6, height: 6)
            case .notTheBug?:
                Text("○")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            case .plantedBug?:
                Text("✕")
                    .font(.caption2)
                    .foregroundColor(TypingPalette.statusError)
            case .differs?:
                Text("≠")
                    .font(.caption2)
                    .foregroundColor(.orange)
            case nil:
                if row.isSkipped {
                    Text("⤼")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.5))
                } else if row.sourceIndex < currentLineIndex {
                    Circle()
                        .fill(TypingPalette.statusClean)
                        .frame(width: 5, height: 5)
                }
            }
        }
    }
}
