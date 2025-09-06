//
//  ToolbarController.swift
//  KamiNeko
//
//  Safari-like titlebar toolbar and centered pill.
//

import AppKit
import SwiftUI

final class BrowserToolbarController: NSObject, NSToolbarDelegate {
    static let shared = BrowserToolbarController()

    private let toolbarIdentifier = NSToolbar.Identifier("KamiNeko.Toolbar")
    // Removed back/forward per UI requirements
    private let undoId = NSToolbarItem.Identifier("KamiNeko.Toolbar.Undo")
    private let redoId = NSToolbarItem.Identifier("KamiNeko.Toolbar.Redo")
    private let newId = NSToolbarItem.Identifier("KamiNeko.Toolbar.New")
    private let openId = NSToolbarItem.Identifier("KamiNeko.Toolbar.Open")
    private let saveId = NSToolbarItem.Identifier("KamiNeko.Toolbar.Save")
    private let themeId = NSToolbarItem.Identifier("KamiNeko.Toolbar.Theme")
    private let newTabId = NSToolbarItem.Identifier("KamiNeko.Toolbar.NewTab")
    private let allTabsId = NSToolbarItem.Identifier("KamiNeko.Toolbar.AllTabs")
    private let zoomId = NSToolbarItem.Identifier("KamiNeko.Toolbar.Zoom")

    private let centerId = NSToolbarItem.Identifier("KamiNeko.Toolbar.Center")
    private var titleLabel: NSTextField?
    private var titleEditField: NSTextField?
    private var zoomSlider: NSSlider?
    private func currentThemeSymbolName() -> String {
        // 浅色显示太阳，深色显示月亮
        let scheme = UserDefaults.standard.string(forKey: "preferredColorScheme") ?? "system"
        switch scheme {
        case "dark": return "moon"
        case "light": return "sun.max"
        default: // system
            switch NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .some(.darkAqua): return "moon"
            default: return "sun.max"
            }
        }
    }

    func attach(to window: NSWindow) {
        let toolbar = NSToolbar(identifier: toolbarIdentifier)
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.sizeMode = .regular
        toolbar.allowsUserCustomization = false
        toolbar.centeredItemIdentifier = centerId
        window.toolbar = toolbar
        window.titleVisibility = .hidden
        if #available(macOS 13.0, *) {
            window.toolbarStyle = .unifiedCompact
        }

        NotificationCenter.default.addObserver(self, selector: #selector(updateTitle(_:)), name: .documentTitleChanged, object: nil)
    }

    // MARK: - Toolbar delegate

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [newId, openId, saveId, .flexibleSpace, centerId, .flexibleSpace, themeId, zoomId, allTabsId]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, centerId, .flexibleSpace, themeId, zoomId, allTabsId]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case centerId:
            let titleField = NSTextField(labelWithString: currentTitle())
            titleField.font = .systemFont(ofSize: 12, weight: .regular)
            titleField.lineBreakMode = .byTruncatingMiddle
            titleField.alignment = .center
            titleField.textColor = .labelColor
            titleField.translatesAutoresizingMaskIntoConstraints = false

            // Save button left of title (disk icon)
            let saveButton = NSButton(image: NSImage(systemSymbolName: "externaldrive", accessibilityDescription: nil)!, target: self, action: #selector(saveFile))
            saveButton.bezelStyle = .texturedRounded
            saveButton.translatesAutoresizingMaskIntoConstraints = false

            let container = NSView()
            container.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(saveButton)
            container.addSubview(titleField)
            NSLayoutConstraint.activate([
                saveButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
                saveButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),

                titleField.leadingAnchor.constraint(equalTo: saveButton.trailingAnchor, constant: 8),
                titleField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
                titleField.centerYAnchor.constraint(equalTo: container.centerYAnchor),

                container.heightAnchor.constraint(equalToConstant: 22),
                container.widthAnchor.constraint(lessThanOrEqualToConstant: 900)
            ])

            let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(beginRename))
            doubleClick.numberOfClicksRequired = 2
            container.addGestureRecognizer(doubleClick)

            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.view = container
            self.titleLabel = titleField
            return item
        
        case undoId:
            return makeButtonItem(id: itemIdentifier, system: "arrow.uturn.backward", action: #selector(undo))
        case redoId:
            return makeButtonItem(id: itemIdentifier, system: "arrow.uturn.forward", action: #selector(redo))
        case newId:
            return makeButtonItem(id: itemIdentifier, system: "doc", action: #selector(newDoc))
        case openId:
            return makeButtonItem(id: itemIdentifier, system: "folder", action: #selector(openFile))
        case saveId:
            return makeButtonItem(id: itemIdentifier, system: "tray.and.arrow.down", action: #selector(saveFile))
        case themeId:
            let button = NSButton(image: NSImage(systemSymbolName: currentThemeSymbolName(), accessibilityDescription: nil)!, target: self, action: #selector(toggleTheme))
            button.bezelStyle = .texturedRounded
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.view = button
            NotificationCenter.default.addObserver(self, selector: #selector(appearanceChanged), name: .appAppearanceChanged, object: nil)
            return item
        case zoomId:
            let slider = NSSlider(value: 14, minValue: 8, maxValue: 64, target: self, action: #selector(zoomSliderChanged(_:)))
            slider.isContinuous = true
            slider.controlSize = .small
            slider.numberOfTickMarks = 0
            slider.translatesAutoresizingMaskIntoConstraints = false
            slider.widthAnchor.constraint(equalToConstant: 140).isActive = true
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.view = slider
            self.zoomSlider = slider
            NotificationCenter.default.addObserver(self, selector: #selector(fontSizeChanged(_:)), name: .editorFontSizeChanged, object: nil)
            return item
        case newTabId:
            return nil
        case allTabsId:
            return makeButtonItem(id: itemIdentifier, system: "square.grid.2x2", action: #selector(showAllTabs))
        default:
            return nil
        }
    }

    private func makeButtonItem(id: NSToolbarItem.Identifier, system: String, action: Selector) -> NSToolbarItem {
        let button = NSButton(image: NSImage(systemSymbolName: system, accessibilityDescription: nil)!, target: self, action: action)
        button.bezelStyle = .texturedRounded
        let item = NSToolbarItem(itemIdentifier: id)
        item.view = button
        return item
    }

    // MARK: - Actions -> broadcast notifications
    // back/forward removed
    @objc private func undo() { NotificationCenter.default.post(name: .toolbarUndo, object: nil) }
    @objc private func redo() { NotificationCenter.default.post(name: .toolbarRedo, object: nil) }
    @objc private func newDoc() { NotificationCenter.default.post(name: .toolbarNewDoc, object: nil) }
    @objc private func openFile() { NotificationCenter.default.post(name: .toolbarOpenFile, object: nil) }
    @objc private func saveFile() { NotificationCenter.default.post(name: .appSaveFile, object: nil) }
    @objc private func toggleTheme() {
        NotificationCenter.default.post(name: .toolbarToggleTheme, object: nil)
        NotificationCenter.default.post(name: .appAppearanceChanged, object: nil)
    }
    @objc private func appearanceChanged() {
        // 延迟一点更新，确保 UserDefaults 已经更新
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let item = (NSApp.keyWindow?.toolbar?.items.first { $0.itemIdentifier == self.themeId }), let button = item.view as? NSButton {
                button.image = NSImage(systemSymbolName: self.currentThemeSymbolName(), accessibilityDescription: nil)
            }
        }
    }
    @objc private func newTab() { NotificationCenter.default.post(name: .toolbarNewTab, object: nil) }
    @objc private func showAllTabs() { NotificationCenter.default.post(name: .toolbarShowAllTabs, object: nil) }
    @objc private func zoomSliderChanged(_ sender: NSSlider) {
        let size = CGFloat(sender.doubleValue)
        NotificationCenter.default.post(name: .editorFontSizeChanged, object: nil, userInfo: ["fontSize": size])
    }

    // MARK: - Title updates
    @objc private func updateTitle(_ note: Notification) {
        // 始终与窗口标题同步（窗口标题已设置为完整路径或文档标题）
        titleLabel?.stringValue = currentTitle()
    }

    private func currentTitle() -> String {
        if let url = NSApp.keyWindow?.representedURL {
            return url.path
        }
        return (NSApp.keyWindow?.title.isEmpty == false ? NSApp.keyWindow?.title : "Untitled")!
    }

    @objc private func fontSizeChanged(_ note: Notification) {
        if let size = note.userInfo? ["fontSize"] as? CGFloat {
            zoomSlider?.doubleValue = Double(size)
        } else if let tv = note.object as? NSTextView, let size = tv.font?.pointSize {
            zoomSlider?.doubleValue = Double(size)
        }
    }

    // MARK: - Rename support
    @objc private func beginRename() {
        guard let label = titleLabel, let superView = label.superview else { return }
        let source = NSApp.keyWindow?.title ?? label.stringValue
        let initial: String = {
            let url = URL(fileURLWithPath: source)
            let name = url.deletingPathExtension().lastPathComponent
            if name.isEmpty { return source }
            return name
        }()
        let editor = NSTextField(string: initial)
        editor.font = label.font
        editor.isBezeled = true
        editor.bezelStyle = .roundedBezel
        editor.drawsBackground = true
        editor.focusRingType = .default
        editor.translatesAutoresizingMaskIntoConstraints = false
        editor.target = self
        editor.action = #selector(commitRename(_:))
        superView.addSubview(editor)
        editor.leadingAnchor.constraint(equalTo: superView.leadingAnchor).isActive = true
        editor.trailingAnchor.constraint(equalTo: superView.trailingAnchor).isActive = true
        editor.centerYAnchor.constraint(equalTo: superView.centerYAnchor).isActive = true
        label.isHidden = true
        self.titleEditField = editor
        superView.window?.makeFirstResponder(editor)
    }

    @objc private func commitRename(_ sender: NSTextField) {
        let newTitle = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if newTitle.isEmpty == false {
            NotificationCenter.default.post(name: .documentRenameRequested, object: nil, userInfo: ["title": newTitle])
            self.titleLabel?.stringValue = currentTitle()
        }
        sender.removeFromSuperview()
        self.titleEditField = nil
        self.titleLabel?.isHidden = false
    }
}


