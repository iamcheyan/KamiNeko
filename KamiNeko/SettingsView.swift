import SwiftUI
import AppKit

struct SettingsView: View {
    @AppStorage("preferredColorScheme") private var preferredSchemeRaw: String = "system"
    @AppStorage("showLineNumbers") private var showLineNumbers: Bool = true
    @AppStorage("enableSyntaxHighlight") private var enableSyntaxHighlight: Bool = true
    @AppStorage("enableAutoSave") private var enableAutoSave: Bool = true
    @AppStorage("editorFontName") private var editorFontName: String = "SFMono-Regular"
    @AppStorage("editorFontSize") private var editorFontSize: Double = 14

    @State private var workingDirPath: String = WorkingDirectoryManager.shared.directoryURL?.path ?? ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("KamiNeko 设置")
                .font(.system(size: 16, weight: .semibold))
                .padding(.top, 8)

            GroupBox(label: Text("外观").font(.headline)) {
                Grid(alignment: .trailingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 12) {
                    GridRow {
                        Text("主题")
                            .frame(minWidth: 80, alignment: .trailing)
                        Picker("", selection: $preferredSchemeRaw) {
                            Text("跟随系统").tag("system")
                            Text("浅色").tag("light")
                            Text("深色").tag("dark")
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: preferredSchemeRaw) {
                            NotificationCenter.default.post(name: .appAppearanceChanged, object: nil)
                            NotificationCenter.default.post(name: .appPreferencesChanged, object: nil)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            GroupBox(label: Text("编辑器").font(.headline)) {
                Grid(alignment: .trailingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 12) {
                    GridRow {
                        Text("自动保存")
                            .frame(minWidth: 80, alignment: .trailing)
                        Toggle("", isOn: $enableAutoSave)
                            .labelsHidden()
                            .onChange(of: enableAutoSave) {
                                NotificationCenter.default.post(name: .appPreferencesChanged, object: nil)
                            }
                    }
                    GridRow {
                        Text("显示行号")
                            .frame(minWidth: 80, alignment: .trailing)
                        Toggle("", isOn: $showLineNumbers)
                            .labelsHidden()
                            .onChange(of: showLineNumbers) {
                                NotificationCenter.default.post(name: .appPreferencesChanged, object: nil)
                            }
                    }
                    GridRow {
                        Text("语法高亮")
                            .frame(minWidth: 80, alignment: .trailing)
                        Toggle("", isOn: $enableSyntaxHighlight)
                            .labelsHidden()
                            .onChange(of: enableSyntaxHighlight) {
                                NotificationCenter.default.post(name: .appPreferencesChanged, object: nil)
                            }
                    }
                    GridRow {
                        Text("字体名")
                            .frame(minWidth: 80, alignment: .trailing)
                        TextField("SFMono-Regular", text: $editorFontName)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 260)
                            .onSubmit { NotificationCenter.default.post(name: .appPreferencesChanged, object: nil) }
                    }
                    GridRow {
                        Text("字号")
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

            GroupBox(label: Text("存储目录").font(.headline)) {
                Grid(alignment: .trailingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 12) {
                    GridRow {
                        Text("路径")
                            .frame(minWidth: 80, alignment: .trailing)
                        HStack(spacing: 8) {
                            TextField("未设置", text: $workingDirPath)
                                .disabled(true)
                                .textFieldStyle(.roundedBorder)
                            Button("选择…") {
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
        .frame(minWidth: 600)
    }
}

extension Notification.Name {
    static let appPreferencesChanged = Notification.Name("KamiNekoPreferencesChanged")
}


