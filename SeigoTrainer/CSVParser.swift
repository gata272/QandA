import Foundation

enum CSVParseError: Error, LocalizedError {
    case unreadableEncoding
    case noQuestions

    var errorDescription: String? {
        switch self {
        case .unreadableEncoding:
            return "ファイルの文字コードを読み取れませんでした（UTF-8 / Shift_JIS に対応しています）"
        case .noQuestions:
            return "問題が1件も見つかりませんでした。形式（番号,表面,裏面,解説）を確認してください"
        }
    }
}

/// 「番号,表面,裏面,解説」形式のCSVを読む。
/// クォート内のカンマ・改行・二重クォート（""）に対応する。
/// 区切りはカンマが基本で、タブ区切り（TSV）も自動判定する。
struct CSVParser {
    static func parse(data: Data) throws -> [Question] {
        guard let text = decode(data) else {
            throw CSVParseError.unreadableEncoding
        }
        let delimiter = detectDelimiter(text)
        let rows = parseRows(text, delimiter: delimiter)
        var questions: [Question] = []
        var sequential = 0
        for (index, row) in rows.enumerated() {
            guard row.count >= 2 else { continue }
            let first = row[0].trimmingCharacters(in: .whitespacesAndNewlines)
            // 1行目がヘッダー（番号などが入っていて数値でない）なら読み飛ばす
            if index == 0 && Int(first) == nil { continue }
            let front = row[1]
            if front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            sequential += 1
            let number = Int(first) ?? sequential
            let back = row.count > 2 ? row[2] : ""
            let explanation = row.count > 3 ? row[3] : ""
            questions.append(Question(number: number, front: front, back: back, explanation: explanation))
        }
        if questions.isEmpty {
            throw CSVParseError.noQuestions
        }
        return questions
    }

    static func decode(_ data: Data) -> String? {
        if let s = String(data: data, encoding: .utf8) {
            if s.hasPrefix("\u{FEFF}") {
                return String(s.dropFirst())
            }
            return s
        }
        if let s = String(data: data, encoding: .shiftJIS) {
            return s
        }
        return nil
    }

    static func detectDelimiter(_ text: String) -> Character {
        let firstLine = text.prefix { $0 != "\n" }
        if firstLine.contains("\t") {
            return "\t"
        }
        return ","
    }

    static func parseRows(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let chars = Array(text)
        var i = 0

        func endField() {
            row.append(field)
            field = ""
        }
        func endRow() {
            endField()
            rows.append(row)
            row = []
        }

        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        field.append("\"")
                        i += 2
                        continue
                    }
                    inQuotes = false
                    i += 1
                    continue
                }
                field.append(c)
                i += 1
                continue
            } else {
                if c == "\"" && field.isEmpty {
                    inQuotes = true
                    i += 1
                    continue
                }
                if c == delimiter {
                    endField()
                    i += 1
                    continue
                }
                if c == "\r" {
                    if i + 1 < chars.count && chars[i + 1] == "\n" {
                        i += 1
                    }
                    endRow()
                    i += 1
                    continue
                }
                if c == "\n" {
                    endRow()
                    i += 1
                    continue
                }
                field.append(c)
                i += 1
                continue
            }
        }
        if !field.isEmpty || !row.isEmpty {
            endRow()
        }
        return rows
    }
}
