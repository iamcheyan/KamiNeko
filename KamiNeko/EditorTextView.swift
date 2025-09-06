//
//  EditorTextView.swift
//  KamiNeko
//
//  NSViewRepresentable wrapping NSTextView with cmd+wheel zoom and line numbers.
//

import SwiftUI
import AppKit

struct EditorTextView: NSViewRepresentable {
    @ObservedObject var document: DocumentModel

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = ZoomableScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.autohidesScrollers = true

        let textView = ZoomableTextView()
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.usesFindBar = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .labelColor
        textView.drawsBackground = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.font = NSFont.monospacedSystemFont(ofSize: document.fontSize, weight: .regular)
        if let container = textView.textContainer {
            container.widthTracksTextView = true
            container.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
            container.lineFragmentPadding = 5
        }

        // Attach document view first
        let layoutManager = textView.layoutManager!
        if #available(macOS 10.15, *) {
            layoutManager.usesDefaultHyphenation = false
        } else {
            layoutManager.hyphenationFactor = 0.0
        }
        scrollView.documentView = textView

        // Line number ruler after documentView is set
        let lineNumberRuler = LineNumberRulerView(textView: textView, scrollView: scrollView)
        scrollView.verticalRulerView = lineNumberRuler
        let showLines = UserDefaults.standard.bool(forKey: "showLineNumbers")
        scrollView.hasVerticalRuler = showLines
        scrollView.rulersVisible = showLines
        textView.textStorage?.delegate = context.coordinator
        textView.string = document.content
        // Apply prefs and observe changes
        context.coordinator.enableSyntaxHighlight = UserDefaults.standard.bool(forKey: "enableSyntaxHighlight")
        context.coordinator.applyPreferences()
        NotificationCenter.default.addObserver(forName: .appPreferencesChanged, object: nil, queue: .main) { _ in
            context.coordinator.applyPreferences()
        }

        // Make first responder if window is available shortly after creation
        DispatchQueue.main.async {
            if let window = scrollView.window { window.makeFirstResponder(textView) }
        }
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        if textView.string != document.content {
            textView.string = document.content
        }
        let currentSize = textView.font?.pointSize ?? 14
        if abs(currentSize - document.fontSize) > 0.5 {
            textView.font = NSFont.monospacedSystemFont(ofSize: document.fontSize, weight: .regular)
        }
        if let container = textView.textContainer, let sv = textView.enclosingScrollView {
            container.widthTracksTextView = true
            container.containerSize = NSSize(width: sv.contentSize.width, height: .greatestFiniteMagnitude)
        }
        // 减少行号标尺的重绘频率
        if abs(currentSize - document.fontSize) > 0.5 {
            (nsView.verticalRulerView as? LineNumberRulerView)?.needsDisplay = true
        }

        // Try to focus the text view when available
        DispatchQueue.main.async {
            if let window = nsView.window, window.firstResponder !== textView {
                window.makeFirstResponder(textView)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(document: document)
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var document: DocumentModel
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        private var lastChange = Date()
        var enableSyntaxHighlight: Bool = true

        init(document: DocumentModel) {
            self.document = document
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            document.content = tv.string
            document.isDirty = true
            lastChange = Date()
            NotificationCenter.default.post(name: .documentEdited, object: nil)
        }

        func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
            guard editedMask.contains(.editedCharacters) else { return }
            guard enableSyntaxHighlight else { return }
            // 只高亮编辑的区域附近，而不是整个文档
            let extendedRange = NSRange(
                location: max(0, editedRange.location - 100),
                length: min(textStorage.length - max(0, editedRange.location - 100), editedRange.length + 200)
            )
            SyntaxHighlighter.highlight(storage: textStorage, in: extendedRange, defaultColor: NSColor.labelColor)
        }

        func applyPreferences() {
            let defaults = UserDefaults.standard
            let showLines = defaults.bool(forKey: "showLineNumbers")
            scrollView?.hasVerticalRuler = showLines
            scrollView?.rulersVisible = showLines
            enableSyntaxHighlight = defaults.bool(forKey: "enableSyntaxHighlight")
        }
    }
}

// 响应设置变更
extension EditorTextView.Coordinator {
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        // reserved
    }
}

final class ZoomableTextView: NSTextView {
    private let currentLineLayer = CALayer()

    private func currentFontLineHeight() -> CGFloat {
        let f = self.font ?? NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        return f.ascender - f.descender + f.leading
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        currentLineLayer.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.10).cgColor
        currentLineLayer.cornerRadius = 3
        layer?.addSublayer(currentLineLayer)
        updateCurrentLineHighlight()
    }

    override var acceptsFirstResponder: Bool { true }
    override func scrollWheel(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) {
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY
            let step: CGFloat = delta > 0 ? 1 : -1
            let current = self.font?.pointSize ?? 14
            let newSize = max(8, min(64, current + step))
            if newSize != current {
                self.font = NSFont.monospacedSystemFont(ofSize: newSize, weight: .regular)
                if let editor = self.enclosingScrollView?.superview?.superview as? NSView { _ = editor }
                // Sync back to model via responder chain notification
                NotificationCenter.default.post(name: .editorFontSizeChanged, object: self, userInfo: ["fontSize": newSize])
                (enclosingScrollView?.verticalRulerView as? LineNumberRulerView)?.needsDisplay = true
                // Do not call super; avoid scrolling when zooming
                return
            }
        }
        super.scrollWheel(with: event)
        // 滚动后更新高亮位置
        updateCurrentLineHighlight()
    }

    override func setSelectedRange(_ charRange: NSRange) {
        super.setSelectedRange(charRange)
        updateCurrentLineHighlight()
    }

    override func didChangeText() {
        super.didChangeText()
        // 延迟更新当前行高亮，避免输入时频繁重绘
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(updateCurrentLineHighlightDelayed), object: nil)
        perform(#selector(updateCurrentLineHighlightDelayed), with: nil, afterDelay: 0.05)
    }
    
    @objc private func updateCurrentLineHighlightDelayed() {
        updateCurrentLineHighlight()
    }

    override func layout() {
        super.layout()
        updateCurrentLineHighlight()
    }

    private func updateCurrentLineHighlight() {
        guard let lm = layoutManager, textContainer != nil else { return }
        guard let range = selectedRanges.first as? NSRange else { return }
        let safeLocation = min(range.location, (string as NSString).length > 0 ? (string as NSString).length - 1 : 0)
        let glyphIndex = lm.glyphIndexForCharacter(at: safeLocation)
        var lineRange = NSRange(location: 0, length: 0)
        let lineRect = lm.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineRange, withoutAdditionalLayout: true)
        let origin = textContainerOrigin
        var frame = CGRect(x: 0, y: lineRect.minY + origin.y, width: bounds.width, height: lineRect.height)
        // 避免在无文本时无限大
        if frame.height.isFinite == false || frame.height <= 0 { frame.size.height = currentFontLineHeight() }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        currentLineLayer.frame = frame
        CATransaction.commit()
    }
}

final class ZoomableScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) {
            if let tv = self.documentView as? NSTextView {
                let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY
                let step: CGFloat = delta > 0 ? 1 : -1
                let current = tv.font?.pointSize ?? 14
                let newSize = max(8, min(64, current + step))
                if newSize != current {
                    tv.font = NSFont.monospacedSystemFont(ofSize: newSize, weight: .regular)
                    NotificationCenter.default.post(name: .editorFontSizeChanged, object: tv, userInfo: ["fontSize": newSize])
                    (self.verticalRulerView as? LineNumberRulerView)?.needsDisplay = true
                    return
                }
            }
        }
        super.scrollWheel(with: event)
    }
}

final class LineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = 34
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = textView, let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return }
        let relativePoint = self.convert(NSZeroPoint, from: textView)
        let visibleRect = self.scrollView?.contentView.bounds ?? .zero
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)

        let context = NSGraphicsContext.current?.cgContext
        context?.setFillColor(NSColor.secondaryLabelColor.withAlphaComponent(0.08).cgColor)
        context?.fill(rect)
        // Right separator line to visually split ruler and content
        let sepX = self.bounds.maxX - 0.5
        context?.setStrokeColor(NSColor.separatorColor.cgColor)
        context?.setLineWidth(1)
        context?.move(to: CGPoint(x: sepX, y: rect.minY))
        context?.addLine(to: CGPoint(x: sepX, y: rect.maxY))
        context?.strokePath()

        var lineNumber = 1
        let textStorageString = textView.string as NSString
        textStorageString.enumerateSubstrings(in: NSRange(location: 0, length: textStorageString.length), options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            if lineRange.upperBound <= glyphRange.location { lineNumber += 1; return }
        }

        var glyphIndex = glyphRange.location
        while glyphIndex < glyphRange.upperBound {
            var lineRange = NSRange(location: 0, length: 0)
            let rect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineRange, withoutAdditionalLayout: true)

            let y = rect.minY + relativePoint.y
            let attr = [NSAttributedString.Key.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                        NSAttributedString.Key.foregroundColor: NSColor.secondaryLabelColor]
            let str = NSAttributedString(string: "\(lineNumber)", attributes: attr)
            let size = str.size()
            let x = self.ruleThickness - size.width - 6
            str.draw(at: NSPoint(x: x, y: y))

            glyphIndex = NSMaxRange(lineRange)
            lineNumber += 1
        }
    }
}

extension Notification.Name {
    static let editorFontSizeChanged = Notification.Name("EditorFontSizeChanged")
    static let appZoomIn = Notification.Name("KamiNekoZoomIn")
    static let appZoomOut = Notification.Name("KamiNekoZoomOut")
    static let appZoomReset = Notification.Name("KamiNekoZoomReset")
    static let appSaveFile = Notification.Name("KamiNekoSaveFile")
    static let appAppearanceChanged = Notification.Name("KamiNekoAppearanceChanged")
    static let toolbarUndo = Notification.Name("KamiNekoToolbarUndo")
    static let toolbarRedo = Notification.Name("KamiNekoToolbarRedo")
    static let toolbarBack = Notification.Name("KamiNekoToolbarBack")
    static let toolbarForward = Notification.Name("KamiNekoToolbarForward")
    static let toolbarNewDoc = Notification.Name("KamiNekoToolbarNewDoc")
    static let toolbarOpenFile = Notification.Name("KamiNekoToolbarOpenFile")
    static let toolbarSaveSession = Notification.Name("KamiNekoToolbarSaveSession")
    static let toolbarToggleTheme = Notification.Name("KamiNekoToolbarToggleTheme")
    static let toolbarNewTab = Notification.Name("KamiNekoToolbarNewTab")
    static let toolbarShowAllTabs = Notification.Name("KamiNekoToolbarShowAllTabs")
    static let documentTitleChanged = Notification.Name("KamiNekoDocumentTitleChanged")
    static let documentRenameRequested = Notification.Name("KamiNekoDocumentRenameRequested")
    static let documentEdited = Notification.Name("KamiNekoDocumentEdited")
}


