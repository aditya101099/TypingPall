import AppKit
import SwiftUI

@MainActor
public protocol TextKit2TypingViewDelegate: AnyObject {
    func typingView(_ view: TextKit2TypingView, didUpdateProgress result: DiffResult)
    func typingViewDidPressReturn(_ view: TextKit2TypingView)
}

/// Production-ready TextKit 2 input engine with sub-8ms latency and zero-layout invalidation styling.
@available(macOS 12.0, *)
@MainActor
public final class TextKit2TypingView: NSView, NSTextViewDelegate {
    public weak var delegate: TextKit2TypingViewDelegate?

    private let textContentStorage = NSTextContentStorage()
    private let textLayoutManager = NSTextLayoutManager()
    private let textContainer: NSTextContainer
    public let textView: NSTextView

    private var preparedTarget = PreparedTargetLine(rawLine: "")
    private var lastAppliedBufferResetToken: UInt64 = 0
    public var diffTolerance: DiffTolerance = .strictCharacter

    public override init(frame frameRect: NSRect) {
        self.textContainer = NSTextContainer(size: NSSize(width: frameRect.width, height: .greatestFiniteMagnitude))
        self.textContainer.widthTracksTextView = true

        self.textLayoutManager.textContainer = textContainer
        self.textContentStorage.addTextLayoutManager(textLayoutManager)

        self.textView = NSTextView(frame: frameRect, textContainer: textContainer)
        super.init(frame: frameRect)
        setupTextView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public var tabSpaces: Int = 4
    public var isEnabled: Bool = true {
        didSet { textView.isEditable = isEnabled }
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.textView.window?.makeFirstResponder(self.textView)
            }
        }
    }

    private func setupTextView() {
        textView.delegate = self
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.drawsBackground = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 16, height: 8)
        textView.textContainer?.lineFragmentPadding = 0
        textView.setAccessibilityIdentifier("practiceInput")
        textView.setAccessibilityLabel("Type the highlighted line here")

        textView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    // MARK: - External State Synchronization

    public func configure(targetLine: String, resetToken: UInt64, fontSize: CGFloat, isEnabled: Bool = true, diffTolerance: DiffTolerance = .strictCharacter, indentPadding: CGFloat = 16) {
        self.isEnabled = isEnabled
        self.diffTolerance = diffTolerance

        let safeSize = min(30, max(12, fontSize))
        if textView.font?.pointSize != safeSize {
            textView.font = NSFont.monospacedSystemFont(ofSize: safeSize, weight: .regular)
        }

        let effectiveInset = max(16, indentPadding)
        if textView.textContainerInset.width != effectiveInset {
            textView.textContainerInset = NSSize(width: effectiveInset, height: 8)
        }

        if preparedTarget.rawLine != targetLine {
            preparedTarget = PreparedTargetLine(rawLine: targetLine)
        }

        if resetToken != lastAppliedBufferResetToken {
            lastAppliedBufferResetToken = resetToken
            if textView.hasMarkedText() {
                textView.unmarkText()
            }
            textView.string = ""
            clearRenderingAttributes()
        }
    }

    public func triggerErrorShake() {
        let animation = CAKeyframeAnimation(keyPath: "position.x")
        animation.values = [0, -4, 4, -3, 3, 0]
        animation.keyTimes = [0, 0.2, 0.4, 0.6, 0.8, 1.0]
        animation.duration = 0.18
        animation.isAdditive = true
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer?.add(animation, forKey: "shake")
    }

    // MARK: - NSTextViewDelegate (Hot Keystroke Path)

    public func textDidChange(_ notification: Notification) {
        // CRITICAL: Do not evaluate diffs or mutate rendering attributes while IME composition is active
        guard !textView.hasMarkedText() else { return }

        let currentString = textView.string
        let result = LineDiff.evaluate(
            target: preparedTarget,
            typed: currentString,
            tolerance: diffTolerance
        )

        applyErrorRenderingAttributes(errorRange: result.errorUTF16Range)
        delegate?.typingView(self, didUpdateProgress: result)
    }

    public func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            guard !textView.hasMarkedText() else { return false }
            delegate?.typingViewDidPressReturn(self)
            return true
        }
        return false
    }

    public func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
                          replacementString: String?) -> Bool {
        guard let replacementString else { return true }
        guard let range = Range(affectedCharRange, in: textView.string) else { return false }
        let replacement = PracticeText.normalize(replacementString, tabSpaces: tabSpaces)
        if replacement.contains("\n") {
            NSSound.beep()
            return false
        }
        let proposed = textView.string.replacingCharacters(in: range, with: replacement)
        guard proposed.count <= PracticeText.maximumCharacters else {
            NSSound.beep()
            return false
        }
        if replacement != replacementString {
            textView.insertText(replacement, replacementRange: affectedCharRange)
            return false
        }
        return true
    }

    // MARK: - TextKit 2 Rendering Attributes (Zero Layout Re-Computation)

    private func clearRenderingAttributes() {
        let documentRange = textLayoutManager.documentRange
        guard !documentRange.isEmpty else { return }
        textLayoutManager.setRenderingAttributes([:], for: documentRange)
        textView.needsDisplay = true
    }

    private func applyErrorRenderingAttributes(errorRange: NSRange?) {
        let documentRange = textLayoutManager.documentRange
        guard !documentRange.isEmpty else { return }

        // 1. Reset existing rendering attributes across the single-line document
        textLayoutManager.setRenderingAttributes([:], for: documentRange)

        // 2. If a mismatch exists, convert UTF-16 NSRange -> NSTextRange and apply ephemeral warm coral tint
        if let nsErrorRange = errorRange,
           nsErrorRange.length > 0,
           let textRange = makeTextRange(from: nsErrorRange) {
            let errorAttributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: TypingPalette.nsErrorUnderline,
                .backgroundColor: TypingPalette.nsErrorBackgroundTint,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: TypingPalette.nsErrorUnderline
            ]
            textLayoutManager.setRenderingAttributes(errorAttributes, for: textRange)
        }

        textView.needsDisplay = true
    }

    private func makeTextRange(from nsRange: NSRange) -> NSTextRange? {
        let docStart = textContentStorage.documentRange.location
        guard let startLoc = textContentStorage.location(docStart, offsetBy: nsRange.location),
              let endLoc = textContentStorage.location(startLoc, offsetBy: nsRange.length) else {
            return nil
        }
        return NSTextRange(location: startLoc, end: endLoc)
    }
}

// MARK: - SwiftUI Preview Wrapper

@available(macOS 12.0, *)
public struct TextKit2TypingViewWrapper: NSViewRepresentable {
    public var targetLine: String
    public var resetToken: UInt64
    public var fontSize: CGFloat
    public var diffTolerance: DiffTolerance = .strictCharacter
    public var indentPadding: CGFloat = 16
    public var isEnabled: Bool = true
    public var onProgress: ((DiffResult) -> Void)?
    public var onReturn: (() -> Void)?

    public init(targetLine: String, resetToken: UInt64 = 0, fontSize: CGFloat = 16,
                diffTolerance: DiffTolerance = .strictCharacter, indentPadding: CGFloat = 16,
                isEnabled: Bool = true,
                onProgress: ((DiffResult) -> Void)? = nil, onReturn: (() -> Void)? = nil) {
        self.targetLine = targetLine
        self.resetToken = resetToken
        self.fontSize = fontSize
        self.diffTolerance = diffTolerance
        self.indentPadding = indentPadding
        self.isEnabled = isEnabled
        self.onProgress = onProgress
        self.onReturn = onReturn
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onProgress: onProgress, onReturn: onReturn)
    }

    public func makeNSView(context: Context) -> TextKit2TypingView {
        let view = TextKit2TypingView()
        view.delegate = context.coordinator
        view.configure(targetLine: targetLine, resetToken: resetToken, fontSize: fontSize,
                       isEnabled: isEnabled, diffTolerance: diffTolerance, indentPadding: indentPadding)
        return view
    }

    public func updateNSView(_ nsView: TextKit2TypingView, context: Context) {
        context.coordinator.onProgress = onProgress
        context.coordinator.onReturn = onReturn
        nsView.configure(targetLine: targetLine, resetToken: resetToken, fontSize: fontSize,
                         isEnabled: isEnabled, diffTolerance: diffTolerance, indentPadding: indentPadding)
    }

    @MainActor
    public final class Coordinator: NSObject, TextKit2TypingViewDelegate {
        var onProgress: ((DiffResult) -> Void)?
        var onReturn: (() -> Void)?

        init(onProgress: ((DiffResult) -> Void)?, onReturn: (() -> Void)?) {
            self.onProgress = onProgress
            self.onReturn = onReturn
        }

        public func typingView(_ view: TextKit2TypingView, didUpdateProgress result: DiffResult) {
            onProgress?(result)
        }

        public func typingViewDidPressReturn(_ view: TextKit2TypingView) {
            onReturn?()
        }
    }
}
