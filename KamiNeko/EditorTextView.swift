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
            // 添加右边距以防止文字被切掉，特别是在没有滚动条时
            let rightMargin: CGFloat = 10
            let availableWidth = max(0, scrollView.contentSize.width - rightMargin)
            container.containerSize = NSSize(width: availableWidth, height: .greatestFiniteMagnitude)
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

        // 注册文件拖拽类型（强化接收 file URL）
        scrollView.registerForDraggedTypes([.fileURL])
        textView.registerForDraggedTypes([.fileURL])

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
        // Mini map
        let miniMap = MiniMapView(textView: textView, scrollView: scrollView)
        miniMap.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(miniMap)
        NSLayoutConstraint.activate([
            miniMap.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -4),
            miniMap.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 4),
            miniMap.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -4),
            miniMap.widthAnchor.constraint(equalToConstant: 72)
        ])
        context.coordinator.miniMap = miniMap
        miniMap.isHidden = !UserDefaults.standard.bool(forKey: "showMiniMap")
        NotificationCenter.default.addObserver(forName: .appPreferencesChanged, object: nil, queue: .main) { _ in
            context.coordinator.applyPreferences()
        }
        
        // 监听滚动视图内容边界变化，确保文本容器尺寸正确
        let contentView = scrollView.contentView
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: contentView, queue: .main) { _ in
            context.coordinator.updateTextContainerSize()
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
            
            // 字体大小改变时，手动触发窗口调整大小通知来更新容器
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak nsView] in
                if let window = nsView?.window {
                    NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: window)
                }
            }
        }
        if let container = textView.textContainer, let sv = textView.enclosingScrollView {
            container.widthTracksTextView = true
            // 添加右边距以防止文字被切掉，特别是在没有滚动条时
            let rightMargin: CGFloat = 10
            let availableWidth = max(0, sv.contentSize.width - rightMargin)
            container.containerSize = NSSize(width: availableWidth, height: .greatestFiniteMagnitude)
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
        weak var miniMap: MiniMapView?
        private var lastChange = Date()
        var enableSyntaxHighlight: Bool = true

        init(document: DocumentModel) {
            self.document = document
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            document.content = tv.string
            document.isDirty = true
            document.updateLastModified()
            lastChange = Date()
            NotificationCenter.default.post(name: .documentEdited, object: nil)
            // 通知仅限当前文档，以避免多个窗口同步错误
            NotificationCenter.default.post(name: .documentContentChanged, object: document)
            miniMap?.setNeedsDisplay(miniMap?.bounds ?? .zero)
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
            miniMap?.isHidden = !defaults.bool(forKey: "showMiniMap")
        }
        
        func updateTextContainerSize() {
            guard let textView = textView, let container = textView.textContainer, let scrollView = scrollView else { return }
            container.widthTracksTextView = true
            // 添加右边距以防止文字被切掉，特别是在没有滚动条时
            let rightMargin: CGFloat = 10
            let availableWidth = max(0, scrollView.contentSize.width - rightMargin)
            container.containerSize = NSSize(width: availableWidth, height: .greatestFiniteMagnitude)
            // 强制重新布局以确保换行正确
            textView.layoutManager?.invalidateLayout(forCharacterRange: NSRange(location: 0, length: textView.string.count), actualCharacterRange: nil)
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

    private func isDarkAppearance() -> Bool {
        return effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private func updateHighlightColor() {
        let alpha: CGFloat = isDarkAppearance() ? 0.12 : 0.06
        currentLineLayer.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(alpha).cgColor
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        updateHighlightColor()
        currentLineLayer.cornerRadius = 3
        layer?.addSublayer(currentLineLayer)
        updateCurrentLineHighlight()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateHighlightColor()
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
                
                // Sync back to model via responder chain notification
                NotificationCenter.default.post(name: .editorFontSizeChanged, object: self, userInfo: ["fontSize": newSize])
                (enclosingScrollView?.verticalRulerView as? LineNumberRulerView)?.needsDisplay = true
                
                // 手动触发窗口调整大小的逻辑，因为那个逻辑是正确的
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
                    if let window = self?.window {
                        NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: window)
                    }
                }
                
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

    // MARK: - Context menu runtime localization
    override func menu(for event: NSEvent) -> NSMenu? {
        let original = super.menu(for: event) ?? NSMenu()
        // Work on a copy to avoid mutating shared templates
        let menu = original.copy() as? NSMenu ?? original
        localizeStandardMenu(menu)
        return menu
    }

    private func localizeStandardMenu(_ menu: NSMenu) {
        for item in menu.items {
            if let action = item.action {
                switch action {
                case #selector(NSText.cut(_:)):
                    item.title = Localizer.t("menu.cut")
                case #selector(NSText.copy(_:)):
                    item.title = Localizer.t("menu.copy")
                case #selector(NSText.paste(_:)):
                    item.title = Localizer.t("menu.paste")
                case #selector(NSText.selectAll(_:)):
                    item.title = Localizer.t("menu.selectAll")
                default:
                    break
                }
            }
            // Fallback by common English titles (system may not expose actions for section headers)
            let title = item.title
            let fallbackMap: [String: String] = [
                "Font": Localizer.t("menu.font"),
                "Spelling and Grammar": Localizer.t("menu.spellingGrammar"),
                "Substitutions": Localizer.t("menu.substitutions"),
                "Transformations": Localizer.t("menu.transformations"),
                "Speech": Localizer.t("menu.speech"),
                "Layout Orientation": Localizer.t("menu.layoutOrientation"),
                "Services": Localizer.t("menu.services"),
                "Show Writing Tools": Localizer.t("menu.showWritingTools"),
                "Proofread": Localizer.t("menu.proofread"),
                "Rewrite": Localizer.t("menu.rewrite")
            ]
            if let localized = fallbackMap[title] {
                item.title = localized
            }
            if let submenu = item.submenu { localizeStandardMenu(submenu) }
        }
        // 追加查找/替换相关项（使用系统查找栏）
        let findMenu = NSMenuItem(title: Localizer.t("menu.find"), action: #selector(NSResponder.performTextFinderAction(_:)), keyEquivalent: "")
        findMenu.tag = NSTextFinder.Action.showFindInterface.rawValue
        let findNext = NSMenuItem(title: Localizer.t("menu.findNext"), action: #selector(NSResponder.performTextFinderAction(_:)), keyEquivalent: "")
        findNext.tag = NSTextFinder.Action.nextMatch.rawValue
        let findPrev = NSMenuItem(title: Localizer.t("menu.findPrevious"), action: #selector(NSResponder.performTextFinderAction(_:)), keyEquivalent: "")
        findPrev.tag = NSTextFinder.Action.previousMatch.rawValue
        let replaceMenu = NSMenuItem(title: Localizer.t("menu.replace"), action: #selector(NSResponder.performTextFinderAction(_:)), keyEquivalent: "")
        replaceMenu.tag = NSTextFinder.Action.showReplaceInterface.rawValue
        let replaceAll = NSMenuItem(title: Localizer.t("menu.replaceAll"), action: #selector(NSResponder.performTextFinderAction(_:)), keyEquivalent: "")
        replaceAll.tag = NSTextFinder.Action.replaceAll.rawValue

        menu.addItem(NSMenuItem.separator())
        menu.addItem(findMenu)
        menu.addItem(findNext)
        menu.addItem(findPrev)
        menu.addItem(replaceMenu)
        menu.addItem(replaceAll)
    }

    // MARK: - Drag & Drop to open files in new tab (prevent path insertion)
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if hasFileURLs(in: sender) { return .copy }
        return super.draggingEntered(sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = readFileURLs(from: sender), urls.isEmpty == false else { return false }
        DispatchQueue.main.async {
            for url in urls {
                NotificationCenter.default.post(name: .openFileURLDropped, object: nil, userInfo: ["url": url])
            }
        }
        return true
    }

    private func hasFileURLs(in sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        let objs = pb.readObjects(forClasses: [NSURL.self], options: [NSPasteboard.ReadingOptionKey.urlReadingFileURLsOnly: true])
        return (objs as? [URL])?.isEmpty == false
    }

    private func readFileURLs(from sender: NSDraggingInfo) -> [URL]? {
        let pb = sender.draggingPasteboard
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [NSPasteboard.ReadingOptionKey.urlReadingFileURLsOnly: true]) as? [URL] {
            return urls
        }
        if let str = pb.string(forType: .fileURL), let url = URL(string: str) { return [url] }
        return nil
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
                    
                    // 手动触发窗口调整大小的逻辑，因为那个逻辑是正确的
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
                        if let window = self?.window {
                            NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: window)
                        }
                    }
                    
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
        let isDark = (self.window?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        context?.setFillColor(NSColor.secondaryLabelColor.withAlphaComponent(isDark ? 0.10 : 0.06).cgColor)
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
            // 根据文本视图的字体大小调整行号字体大小，但保持相对较小
            let textFontSize = textView.font?.pointSize ?? 14
            let rulerFontSize = max(9, min(13, textFontSize * 0.8))
            let attr = [NSAttributedString.Key.font: NSFont.monospacedSystemFont(ofSize: rulerFontSize, weight: .regular),
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

// MARK: - Mini map (文本地图)
final class MiniMapView: NSView {
    weak var textView: NSTextView?
    weak var scrollView: NSScrollView?
    private var observers: [NSObjectProtocol] = []

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        self.scrollView = scrollView
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1
        startObserving()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { stopObserving() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let tv = textView else { return }
        let context = NSGraphicsContext.current?.cgContext
        let isDark = (self.window?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        let bg = NSColor.secondaryLabelColor.withAlphaComponent(isDark ? 0.06 : 0.04)
        context?.setFillColor(bg.cgColor)
        context?.fill(bounds)

        // 基于行做密度渲染
        let ns = tv.string as NSString
        let totalLen = ns.length
        if totalLen == 0 { return }

        var lineRanges: [NSRange] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: totalLen), options: [.byLines, .substringNotRequired]) { _, range, _, _ in
            lineRanges.append(range)
        }
        let totalLines = max(1, lineRanges.count)
        let unit = max(1.0, bounds.height / CGFloat(totalLines))

        let activeColor = NSColor.labelColor.withAlphaComponent(isDark ? 0.35 : 0.25)
        let passiveColor = NSColor.labelColor.withAlphaComponent(isDark ? 0.15 : 0.10)

        for (idx, r) in lineRanges.enumerated() {
            let y = CGFloat(idx) * unit
            let h = ceil(unit)
            let hasText = ns.substring(with: r).trimmingCharacters(in: .whitespaces).isEmpty == false
            context?.setFillColor((hasText ? activeColor : passiveColor).cgColor)
            context?.fill(CGRect(x: 2, y: y, width: bounds.width - 4, height: h))
        }

        // 可视区域高亮
        if let lm = tv.layoutManager, let tc = tv.textContainer {
            let visibleRect = scrollView?.contentView.bounds ?? .zero
            let glyphRange = lm.glyphRange(forBoundingRect: visibleRect, in: tc)
            // 计算顶部与底部行索引
            var topIndex = 0
            var bottomIndex = totalLines - 1
            var ln = 0
            ns.enumerateSubstrings(in: NSRange(location: 0, length: totalLen), options: [.byLines, .substringNotRequired]) { _, range, _, stop in
                if range.upperBound <= glyphRange.location { ln += 1; return }
                if topIndex == 0 { topIndex = ln }
                if range.location >= NSMaxRange(glyphRange) { bottomIndex = max(ln, topIndex); stop.pointee = true; return }
                ln += 1
            }
            let y1 = CGFloat(topIndex) * unit
            let y2 = CGFloat(min(bottomIndex + 1, totalLines)) * unit
            let accent = NSColor.controlAccentColor.withAlphaComponent(isDark ? 0.35 : 0.25)
            context?.setFillColor(accent.cgColor)
            context?.fill(CGRect(x: 1, y: y1, width: bounds.width - 2, height: max(6, y2 - y1)))
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let tv = textView else { return }
        let point = convert(event.locationInWindow, from: nil)
        scrollToMiniMapY(point.y, in: tv)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let tv = textView else { return }
        let point = convert(event.locationInWindow, from: nil)
        scrollToMiniMapY(point.y, in: tv)
    }

    private func scrollToMiniMapY(_ y: CGFloat, in tv: NSTextView) {
        let ns = tv.string as NSString
        var lineStarts: [Int] = [0]
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines, .substringNotRequired]) { _, range, _, _ in
            lineStarts.append(range.upperBound)
        }
        let totalLines = max(1, lineStarts.count - 1)
        let unit = max(1.0, bounds.height / CGFloat(totalLines))
        let idx = min(max(Int(floor(y / unit)), 0), totalLines - 1)
        let charIndex = lineStarts[idx]
        tv.scrollRangeToVisible(NSRange(location: charIndex, length: 0))
        needsDisplay = true
    }

    private func startObserving() {
        guard observers.isEmpty else { return }
        if let cv = scrollView?.contentView {
            cv.postsBoundsChangedNotifications = true
            let o = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: cv, queue: .main) { [weak self] _ in
                self?.needsDisplay = true
            }
            observers.append(o)
        }
        if let tv = textView {
            let o1 = NotificationCenter.default.addObserver(forName: NSText.didChangeNotification, object: tv, queue: .main) { [weak self] _ in
                self?.needsDisplay = true
            }
            observers.append(o1)
        }
    }

    private func stopObserving() {
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers.removeAll()
    }
}

extension Notification.Name {
    static let editorFontSizeChanged = Notification.Name("EditorFontSizeChanged")
    static let appZoomIn = Notification.Name("KamiNekoZoomIn")
    static let appZoomOut = Notification.Name("KamiNekoZoomOut")
    static let appZoomReset = Notification.Name("KamiNekoZoomReset")
    static let appSaveFile = Notification.Name("KamiNekoSaveFile")
    static let appAppearanceChanged = Notification.Name("KamiNekoAppearanceChanged")
    static let appDeleteCurrent = Notification.Name("KamiNekoDeleteCurrentFileAndCloseTab")
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
    static let documentContentChanged = Notification.Name("KamiNekoDocumentContentChanged")
    static let openFileURLDropped = Notification.Name("KamiNekoOpenFileURLDropped")
}


