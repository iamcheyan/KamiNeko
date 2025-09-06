//
//  SyntaxHighlighter.swift
//  KamiNeko
//
//  Minimal regex-based syntax highlighting (Swift-like keywords)
//

import AppKit

enum SyntaxHighlighter {
    static let keywordColor = NSColor.systemPurple
    static let typeColor = NSColor.systemTeal
    static let stringColor = NSColor.systemRed
    static let numberColor = NSColor.systemOrange
    static let commentColor = NSColor.systemGreen

    static let keywords: Set<String> = [
        "let","var","func","if","else","for","while","repeat","switch","case","default","break","continue","return","import","in","where","guard","do","catch","try","as","is","class","struct","enum","protocol","extension","init","deinit","public","private","fileprivate","internal","open","static","throws","rethrows","async","await","nil","true","false"
    ]

    static func highlight(storage: NSTextStorage, in range: NSRange) {
        guard range.location != NSNotFound, range.length > 0 else { return }

        // Reset attributes to default foreground color to avoid color accumulation
        storage.removeAttribute(.foregroundColor, range: range)

        let string = storage.string as NSString

        // Comments // ...
        let commentPattern = "//.*$"
        applyRegex(pattern: commentPattern, string: string, in: range, options: [.anchorsMatchLines]) { matchRange in
            storage.addAttribute(.foregroundColor, value: commentColor, range: matchRange)
        }

        // Strings "..." (simple, not handling escapes comprehensively)
        let stringPattern = "\"[^\"\\]*(?:\\.[^\"\\]*)*\""
        applyRegex(pattern: stringPattern, string: string, in: range) { matchRange in
            storage.addAttribute(.foregroundColor, value: stringColor, range: matchRange)
        }

        // Numbers
        let numberPattern = "\\b[0-9]+(?:\\.[0-9]+)?\\b"
        applyRegex(pattern: numberPattern, string: string, in: range) { matchRange in
            storage.addAttribute(.foregroundColor, value: numberColor, range: matchRange)
        }

        // Types (start with uppercase letter)
        let typePattern = "\\b[A-Z][A-Za-z0-9_]*\\b"
        applyRegex(pattern: typePattern, string: string, in: range) { matchRange in
            storage.addAttribute(.foregroundColor, value: typeColor, range: matchRange)
        }

        // Keywords
        let wordsPattern = "\\b([A-Za-z_][A-Za-z0-9_]*)\\b"
        applyRegex(pattern: wordsPattern, string: string, in: range) { matchRange in
            let word = string.substring(with: matchRange)
            if keywords.contains(word) {
                storage.addAttribute(.foregroundColor, value: keywordColor, range: matchRange)
            }
        }
    }

    private static func applyRegex(pattern: String, string: NSString, in range: NSRange, options: NSRegularExpression.Options = [], apply: (NSRange) -> Void) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        let results = regex.matches(in: string as String, options: [], range: range)
        for r in results { apply(r.range) }
    }
}


