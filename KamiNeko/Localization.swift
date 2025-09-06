import Foundation

enum Localizer {
    private static func currentLang() -> String {
        let pref = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
        if pref == "system" {
            let sys = Locale.preferredLanguages.first ?? "en"
            if sys.hasPrefix("zh") { return "zh-Hans" }
            if sys.hasPrefix("ja") { return "ja" }
            return "en"
        }
        return pref
    }

    static func t(_ key: String) -> String {
        let lang = currentLang()
        return (table[key]?[lang]) ?? (table[key]?["en"] ?? key)
    }

    // 简易内置多语言表，避免依赖工程资源配置
    private static let table: [String: [String: String]] = [
        // Generic
        "untitled": ["zh-Hans": "未命名", "en": "Untitled", "ja": "名称未設定"],

        // Settings
        "settings.title": ["zh-Hans": "KamiNeko 设置", "en": "KamiNeko Settings", "ja": "KamiNeko 設定"],
        "appearance.section": ["zh-Hans": "外观", "en": "Appearance", "ja": "外観"],
        "appearance.theme": ["zh-Hans": "主题", "en": "Theme", "ja": "テーマ"],
        "appearance.language": ["zh-Hans": "语言", "en": "Language", "ja": "言語"],
        "theme.system": ["zh-Hans": "跟随系统", "en": "System", "ja": "システム"],
        "theme.light": ["zh-Hans": "浅色", "en": "Light", "ja": "ライト"],
        "theme.dark": ["zh-Hans": "深色", "en": "Dark", "ja": "ダーク"],
        "lang.system": ["zh-Hans": "跟随系统", "en": "System", "ja": "システム"],
        "lang.zh": ["zh-Hans": "中文", "en": "Chinese", "ja": "中国語"],
        "lang.en": ["zh-Hans": "English", "en": "English", "ja": "英語"],
        "lang.ja": ["zh-Hans": "日本語", "en": "Japanese", "ja": "日本語"],

        "editor.section": ["zh-Hans": "编辑器", "en": "Editor", "ja": "エディタ"],
        "editor.autoSave": ["zh-Hans": "自动保存", "en": "Auto Save", "ja": "自動保存"],
        "editor.showLineNumbers": ["zh-Hans": "显示行号", "en": "Line Numbers", "ja": "行番号"],
        "editor.syntaxHighlight": ["zh-Hans": "语法高亮", "en": "Syntax Highlight", "ja": "構文ハイライト"],
        "editor.fontName": ["zh-Hans": "字体名", "en": "Font Name", "ja": "フォント名"],
        "editor.fontSize": ["zh-Hans": "字号", "en": "Font Size", "ja": "文字サイズ"],

        "storage.section": ["zh-Hans": "存储目录", "en": "Working Directory", "ja": "作業ディレクトリ"],
        "storage.path": ["zh-Hans": "路径", "en": "Path", "ja": "パス"],
        "storage.choose": ["zh-Hans": "选择…", "en": "Choose…", "ja": "選択…"],

        "restart.title": ["zh-Hans": "需要重启", "en": "Restart Required", "ja": "再起動が必要です"],
        "restart.message": ["zh-Hans": "更改语言将在重启后生效。是否立即重启应用？", "en": "Language change takes effect after restart. Restart now?", "ja": "言語の変更は再起動後に反映されます。今すぐ再起動しますか？"],
        "restart.later": ["zh-Hans": "稍后", "en": "Later", "ja": "後で"],
        "restart.now": ["zh-Hans": "立即重启", "en": "Restart Now", "ja": "今すぐ再起動"],

        // ContentView
        "content.placeholder": ["zh-Hans": "新建文档或打开文件", "en": "Create a document or open a file", "ja": "新規作成またはファイルを開く"],
        "tabs.count": ["zh-Hans": "已打开标签：", "en": "Open tabs: ", "ja": "開いているタブ："],
    ]
}


