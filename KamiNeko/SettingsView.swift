import SwiftUI
import AppKit

struct SettingsView: View {
    @AppStorage("preferredColorScheme") private var preferredSchemeRaw: String = "system"
    @AppStorage("showLineNumbers") private var showLineNumbers: Bool = true
    @AppStorage("enableSyntaxHighlight") private var enableSyntaxHighlight: Bool = true
    @AppStorage("enableAutoSave") private var enableAutoSave: Bool = true
    @AppStorage("editorFontName") private var editorFontName: String = "SFMono-Regular"
    @AppStorage("editorFontSize") private var editorFontSize: Double = 14
    @AppStorage("appLanguage") private var appLanguage: String = "system" // system, zh-Hans, en, ja

    @State private var workingDirPath: String = WorkingDirectoryManager.shared.directoryURL?.path ?? ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(Localizer.t("settings.title"))
                .font(.system(size: 16, weight: .semibold))
                .padding(.top, 8)

            // 外观组：保留语言，去掉主题
            GroupBox(label: Text(Localizer.t("appearance.section")).font(.headline)) {
                Grid(alignment: .trailingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 12) {
                    GridRow {
                        Text(Localizer.t("appearance.language"))
                            .frame(minWidth: 80, alignment: .trailing)
                        Picker("", selection: $appLanguage) {
                            Text(Localizer.t("lang.system")).tag("system")
                            Text(Localizer.t("lang.zh")).tag("zh-Hans")
                            Text(Localizer.t("lang.en")).tag("en")
                            Text(Localizer.t("lang.ja")).tag("ja")
                        }
                        .onChange(of: appLanguage) {
                            applyLanguageChange(appLanguage)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            GroupBox(label: Text(Localizer.t("editor.section")).font(.headline)) {
                Grid(alignment: .trailingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 12) {
                    GridRow {
                        Text(Localizer.t("editor.autoSave"))
                            .frame(minWidth: 80, alignment: .trailing)
                        Toggle("", isOn: $enableAutoSave)
                            .labelsHidden()
                            .onChange(of: enableAutoSave) {
                                NotificationCenter.default.post(name: .appPreferencesChanged, object: nil)
                            }
                    }
                    GridRow {
                        Text(Localizer.t("editor.showLineNumbers"))
                            .frame(minWidth: 80, alignment: .trailing)
                        Toggle("", isOn: $showLineNumbers)
                            .labelsHidden()
                            .onChange(of: showLineNumbers) {
                                NotificationCenter.default.post(name: .appPreferencesChanged, object: nil)
                            }
                    }
                    GridRow {
                        Text(Localizer.t("editor.syntaxHighlight"))
                            .frame(minWidth: 80, alignment: .trailing)
                        Toggle("", isOn: $enableSyntaxHighlight)
                            .labelsHidden()
                            .onChange(of: enableSyntaxHighlight) {
                                NotificationCenter.default.post(name: .appPreferencesChanged, object: nil)
                            }
                    }
                    GridRow {
                        Text(Localizer.t("editor.fontName"))
                            .frame(minWidth: 80, alignment: .trailing)
                        FontPicker(selectedFontName: $editorFontName)
                            .frame(minWidth: 260)
                            .onChange(of: editorFontName) {
                                NotificationCenter.default.post(name: .appPreferencesChanged, object: nil)
                            }
                    }
                    GridRow {
                        Text(Localizer.t("editor.fontSize"))
                            .frame(minWidth: 80, alignment: .trailing)
                        HStack(spacing: 10) {
                            Slider(value: $editorFontSize, in: 8...48, step: 1) { Text("") }
                                .frame(minWidth: 260)
                            Text("\(Int(editorFontSize))")
                                .monospacedDigit()
                                .frame(width: 32, alignment: .trailing)
                        }
                        .onChange(of: editorFontSize) {
                            NotificationCenter.default.post(name: .editorFontSizeChanged, object: nil, userInfo: ["fontSize": CGFloat(editorFontSize)])
                            NotificationCenter.default.post(name: .appPreferencesChanged, object: nil)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            GroupBox(label: Text(Localizer.t("storage.section")).font(.headline)) {
                Grid(alignment: .trailingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 12) {
                    GridRow {
                        Text(Localizer.t("storage.path"))
                            .frame(minWidth: 80, alignment: .trailing)
                        HStack(spacing: 8) {
                            TextField("-", text: $workingDirPath)
                                .disabled(true)
                                .textFieldStyle(.roundedBorder)
                            Button(Localizer.t("storage.choose")) {
                                if let url = WorkingDirectoryManager.shared.promptUserToChooseDirectory() {
                                    workingDirPath = url.path
                                }
                            }
                        }
                        .frame(minWidth: 260)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minWidth: 480)
    }

    private func applyLanguageChange(_ lang: String) {
        let defaults = UserDefaults.standard
        if lang == "system" {
            defaults.removeObject(forKey: "AppleLanguages")
        } else {
            defaults.set([lang], forKey: "AppleLanguages")
        }
        defaults.synchronize()
        let alert = NSAlert()
        alert.messageText = Localizer.t("restart.title")
        alert.informativeText = Localizer.t("restart.message")
        alert.addButton(withTitle: Localizer.t("restart.later"))
        alert.addButton(withTitle: Localizer.t("restart.now"))
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            NSApp.terminate(nil)
        }
    }
}

extension Notification.Name {
    static let appPreferencesChanged = Notification.Name("KamiNekoPreferencesChanged")
}

// 系统字体选择器（基于 NSFontPanel）
struct FontPicker: NSViewRepresentable {
    @Binding var selectedFontName: String

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: selectedFontName, target: context.coordinator, action: #selector(Coordinator.pick))
        button.bezelStyle = .rounded
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        nsView.title = selectedFontName
    }

    func makeCoordinator() -> Coordinator { Coordinator(owner: self) }

    final class Coordinator: NSObject, NSFontChanging {
        let owner: FontPicker
        init(owner: FontPicker) { self.owner = owner }

        @objc func pick() {
            let panel = NSFontPanel.shared
            panel.setPanelFont(NSFont(name: owner.selectedFontName, size: 14) ?? NSFont.monospacedSystemFont(ofSize: 14, weight: .regular), isMultiple: false)
            panel.makeKeyAndOrderFront(nil)
            NSFontManager.shared.target = self
        }

        func changeFont(_ sender: NSFontManager?) {
            guard let fontManager = sender else { return }
            let font = fontManager.convert(NSFont.systemFont(ofSize: 14))
            owner.selectedFontName = font.fontName
        }
    }
}


