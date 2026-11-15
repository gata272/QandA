import Foundation
import ZIPFoundation

enum ZipImportError: Error, LocalizedError {
    case cannotOpen
    case noCSVInside

    var errorDescription: String? {
        switch self {
        case .cannotOpen:
            return "ZIPファイルを展開できませんでした"
        case .noCSVInside:
            return "ZIPの中にCSVファイルが見つかりませんでした"
        }
    }
}

/// ZIPの中にある CSV / TSV / TXT をすべて読み、それぞれを1つの問題集として返す。
/// 読めなかったファイルは failures に（名前, 理由）で返す。
enum ZipImporter {
    static func extractQuestionSets(data: Data) throws -> (sets: [(name: String, questions: [Question])],
                                                           failures: [(name: String, message: String)]) {
        guard let archive = try? Archive(data: data, accessMode: .read) else {
            throw ZipImportError.cannotOpen
        }
        var sets: [(name: String, questions: [Question])] = []
        var failures: [(name: String, message: String)] = []
        for entry in archive where entry.type == .file {
            let path = entry.path
            if path.hasPrefix("__MACOSX/") || path.hasSuffix(".DS_Store") { continue }
            let ext = (path as NSString).pathExtension.lowercased()
            guard ["csv", "tsv", "txt"].contains(ext) else { continue }
            let baseName = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            do {
                var d = Data()
                _ = try archive.extract(entry) { chunk in d.append(chunk) }
                let questions = try CSVParser.parse(data: d)
                sets.append((name: baseName, questions: questions))
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                failures.append((name: baseName, message: message))
            }
        }
        if sets.isEmpty && failures.isEmpty {
            throw ZipImportError.noCSVInside
        }
        return (sets, failures)
    }
}
