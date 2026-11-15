import Foundation

enum CSVParseError: Error, LocalizedError {
    case emptyFile
    case zipFile
    case pdfFile
    case unreadableEncoding
    case noQuestions(rows: Int, bytes: Int)

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "ファイルの中身が空でした。iCloud上のファイルの場合は、ファイルアプリでダウンロードを完了させてから選び直してください"
        case .zipFile:
            return "ZIPファイルが選ばれています。解凍して中身のCSVファイルを選んでください"
        case .pdfFile:
            return "PDFファイルが選ばれています。CSVファイルを選んでください"
        case .unreadableEncoding:
            return "ファイルの文字コードを読み取れませんでした（UTF-8 / UTF-16 / Shift_JIS に対応しています）"
        case .noQuestions(let rows, let bytes):
            return "問題が1件も見つかりませんでした。形式（番号,表面,裏面,解説）を確認してください（読み取れた行数：\(rows)、ファイルサイズ：\(bytes)バイト）"
        }
    }
}

/// 「番号,表面,裏面,解説」形式のCSVを読む。
/// クォート内のカンマ・改行・二重クォート（""）に対応する。
/// 区切り文字はカンマ／タブ／セミコロン／全角カンマから自動判定する。
struct CSVParser {
    static func parse(data: Data) throws -> [Question] {
        if data.isEmpty {
            throw CSVParseError.emptyFile
        }
        // ZIP / PDF を間違えて選んだ場合は専用の案内を出す
        let head = [UInt8](data.prefix(4))
        if head.count >= 2 && head[0] == 0x50 && head[1] == 0x4B {
            throw CSVParseError.zipFile
        }
        if head.count >= 4 && head[0] == 0x25 && head[1] == 0x50 && head[2] == 0x44 && head[3] == 0x46 {
            throw CSVParseError.pdfFile
        }
        guard let text = decode(data) else {
            throw CSVParseError.unreadableEncoding
        }

        // 区切り文字の候補を順に試し、問題が取れたものを採用する
        let candidates = delimiterCandidates(text)
        var bestRows = 0
        for delimiter in candidates {
            let rows = parseRows(text, delimiter: delimiter)
            bestRows = max(bestRows, rows.count)
            let questions = questions(from: rows)
            if !questions.isEmpty {
                return questions
            }
        }
        throw CSVParseError.noQuestions(rows: bestRows, bytes: data.count)
    }

    static func questions(from rows: [[String]]) -> [Question] {
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
        return questions
    }

    static func decode(_ data: Data) -> String? {
        // UTF-8（BOM可）
        if let s = String(data: data, encoding: .utf8) {
            return stripBOM(s)
        }
        // UTF-16（BOMで LE/BE を判定）
        if let s = String(data: data, encoding: .utf16) {
            return stripBOM(s)
        }
        // Shift_JIS
        if let s = String(data: data, encoding: .shiftJIS) {
            return stripBOM(s)
        }
        return nil
    }

    static func stripBOM(_ s: String) -> String {
        if s.hasPrefix("\u{FEFF}") {
            return String(s.dropFirst())
        }
        return s
    }

    /// 最初の数行に多く現れる区切り文字を優先して候補を返す。
    static func delimiterCandidates(_ text: String) -> [Unicode.Scalar] {
        let sample = text.unicodeScalars.prefix(4000)
        var counts: [Unicode.Scalar: Int] = [:]
        let all: [Unicode.Scalar] = [",", "\t", ";", "，"]
        for scalar in sample where all.contains(scalar) {
            counts[scalar, default: 0] += 1
        }
        let sorted = all.sorted { (counts[$0] ?? 0) > (counts[$1] ?? 0) }
        return sorted
    }

    /// 文字ではなく Unicode スカラー単位で走査する。
    /// （Swift の Character では CRLF が1文字に合体してしまい、改行判定をすり抜けるため）
    static func parseRows(_ text: String, delimiter: Unicode.Scalar) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let scalars = Array(text.unicodeScalars)
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

        while i < scalars.count {
            let c = scalars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < scalars.count && scalars[i + 1] == "\"" {
                        field.unicodeScalars.append("\"")
                        i += 2
                        continue
                    }
                    inQuotes = false
                    i += 1
                    continue
                }
                field.unicodeScalars.append(c)
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
                    if i + 1 < scalars.count && scalars[i + 1] == "\n" {
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
                field.unicodeScalars.append(c)
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
