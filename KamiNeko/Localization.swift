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
        "editor.miniMap": ["zh-Hans": "显示文本地图", "en": "Show Mini Map", "ja": "テキストマップを表示"],
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

        // Context menu common items
        "menu.cut": ["zh-Hans": "剪切", "en": "Cut", "ja": "カット"],
        "menu.copy": ["zh-Hans": "复制", "en": "Copy", "ja": "コピー"],
        "menu.paste": ["zh-Hans": "粘贴", "en": "Paste", "ja": "ペースト"],
        "menu.selectAll": ["zh-Hans": "全选", "en": "Select All", "ja": "すべてを選択"],
        "menu.font": ["zh-Hans": "字体", "en": "Font", "ja": "フォント"],
        "menu.spellingGrammar": ["zh-Hans": "拼写与语法", "en": "Spelling and Grammar", "ja": "スペルと文法"],
        "menu.substitutions": ["zh-Hans": "替换", "en": "Substitutions", "ja": "置換"],
        "menu.transformations": ["zh-Hans": "转换", "en": "Transformations", "ja": "変換"],
        "menu.speech": ["zh-Hans": "语音", "en": "Speech", "ja": "スピーチ"],
        "menu.layoutOrientation": ["zh-Hans": "版式方向", "en": "Layout Orientation", "ja": "レイアウトの方向"],
        "menu.showWritingTools": ["zh-Hans": "显示写作工具", "en": "Show Writing Tools", "ja": "ライティングツールを表示"],
        "menu.proofread": ["zh-Hans": "校对", "en": "Proofread", "ja": "校正"],
        "menu.rewrite": ["zh-Hans": "改写", "en": "Rewrite", "ja": "書き直し"],
        // Find/Replace
        "menu.find": ["zh-Hans": "查找…", "en": "Find…", "ja": "検索…"],
        "menu.findNext": ["zh-Hans": "查找下一个", "en": "Find Next", "ja": "次を検索"],
        "menu.findPrevious": ["zh-Hans": "查找上一个", "en": "Find Previous", "ja": "前を検索"],
        "menu.replace": ["zh-Hans": "替换…", "en": "Replace…", "ja": "置換…"],
        "menu.replaceAll": ["zh-Hans": "全部替换", "en": "Replace All", "ja": "すべて置換"],

        // App main menu (Application menu) templates
        // Use String(format:) with one %@ placeholder for app name
        "menu.aboutApp": ["zh-Hans": "关于 %@", "en": "About %@", "ja": "%@ について"],
        "menu.settings": ["zh-Hans": "设置…", "en": "Settings…", "ja": "設定…"],
        "menu.services": ["zh-Hans": "服务", "en": "Services", "ja": "サービス"],
        "menu.hideApp": ["zh-Hans": "隐藏 %@", "en": "Hide %@", "ja": "%@ を隠す"],
        "menu.hideOthers": ["zh-Hans": "隐藏其他", "en": "Hide Others", "ja": "ほかを隠す"],
        "menu.showAll": ["zh-Hans": "全部显示", "en": "Show All", "ja": "すべてを表示"],
        "menu.quitApp": ["zh-Hans": "退出 %@", "en": "Quit %@", "ja": "%@ を終了"],

        // Top menu bar titles
        "menu.file": ["zh-Hans": "文件", "en": "File", "ja": "ファイル"],
        "menu.edit": ["zh-Hans": "编辑", "en": "Edit", "ja": "編集"],
        "menu.view": ["zh-Hans": "显示", "en": "View", "ja": "表示"],
        "menu.window": ["zh-Hans": "窗口", "en": "Window", "ja": "ウインドウ"],
        "menu.help": ["zh-Hans": "帮助", "en": "Help", "ja": "ヘルプ"],

        // Tab / Window menu items
        "menu.closeTab": ["zh-Hans": "关闭标签", "en": "Close Tab", "ja": "タブを閉じる"],
        "menu.closeOtherTabs": ["zh-Hans": "关闭其他标签", "en": "Close Other Tabs", "ja": "ほかのタブを閉じる"],
        "menu.moveTabToNewWindow": ["zh-Hans": "将标签移至新窗口", "en": "Move Tab to New Window", "ja": "タブを新規ウインドウに移動"],
        "menu.showAllTabs": ["zh-Hans": "显示所有标签", "en": "Show All Tabs", "ja": "すべてのタブを表示"],
        "menu.showTabBar": ["zh-Hans": "显示标签栏", "en": "Show Tab Bar", "ja": "タブバーを表示"],
        "menu.hideTabBar": ["zh-Hans": "隐藏标签栏", "en": "Hide Tab Bar", "ja": "タブバーを隠す"],

        // File menu common items
        "menu.newWindow": ["zh-Hans": "新建窗口", "en": "New Window", "ja": "新規ウインドウ"],
        "menu.closeWindow": ["zh-Hans": "关闭窗口", "en": "Close Window", "ja": "ウインドウを閉じる"],
        "menu.closeTabFile": ["zh-Hans": "关闭标签", "en": "Close Tab", "ja": "タブを閉じる"],
        // View menu extras
        "view.showFindBar": ["zh-Hans": "显示查找栏", "en": "Show Find Bar", "ja": "検索バーを表示"]
    ]
}


