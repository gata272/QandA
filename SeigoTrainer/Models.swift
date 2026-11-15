import Foundation

struct Question: Codable, Identifiable, Equatable {
    var number: Int
    var front: String
    var back: String
    var explanation: String
    var id: Int { number }
}

struct QuestionStat: Codable, Equatable {
    var correctCount: Int = 0
    var wrongCount: Int = 0
    var lastCorrect: Bool? = nil
}

struct QuestionSetFile: Codable {
    var id: String
    var name: String
    var importedAt: Date
    var questions: [Question]
}

struct LoadedSet: Identifiable {
    var id: String
    var name: String
    var importedAt: Date
    var questions: [Question]
    var stats: [Int: QuestionStat]

    var wrongRemaining: Int {
        stats.values.filter { $0.lastCorrect == false }.count
    }
    var minNumber: Int { questions.map { $0.number }.min() ?? 1 }
    var maxNumber: Int { questions.map { $0.number }.max() ?? 1 }
}

/// 問題集（CSVから読み込んだ問題の集まり）をアプリ内にファイルとして保持する。
/// 保存先は Documents/SeigoTrainerSets。ファイル名だけを手がかりに、起動のたびに
/// 現在の Documents から読み直す（LiveContainer で保存パスが変わっても壊れないように）。
final class SetStore: ObservableObject {
    @Published var sets: [LoadedSet] = []

    init() {
        load()
    }

    private func setsDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("SeigoTrainerSets", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func setFileURL(id: String) -> URL {
        setsDirectory().appendingPathComponent("\(id).json")
    }

    private func statsFileURL(id: String) -> URL {
        setsDirectory().appendingPathComponent("\(id).stats.json")
    }

    func load() {
        let dir = setsDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var loaded: [LoadedSet] = []
        for url in files where url.pathExtension == "json" && !url.lastPathComponent.hasSuffix(".stats.json") {
            guard let data = try? Data(contentsOf: url),
                  let file = try? decoder.decode(QuestionSetFile.self, from: data) else {
                continue
            }
            var stats: [Int: QuestionStat] = [:]
            if let sdata = try? Data(contentsOf: statsFileURL(id: file.id)),
               let decoded = try? decoder.decode([Int: QuestionStat].self, from: sdata) {
                stats = decoded
            }
            loaded.append(LoadedSet(id: file.id, name: file.name, importedAt: file.importedAt, questions: file.questions, stats: stats))
        }
        sets = loaded.sorted { $0.importedAt > $1.importedAt }
    }

    private func writeSetFile(_ file: QuestionSetFile) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(file)
        try data.write(to: setFileURL(id: file.id), options: .atomic)
    }

    private func writeStats(id: String, stats: [Int: QuestionStat]) {
        if let data = try? JSONEncoder().encode(stats) {
            try? data.write(to: statsFileURL(id: id), options: .atomic)
        }
    }

    @discardableResult
    func addSet(name: String, questions: [Question], stats: [Int: QuestionStat] = [:]) throws -> LoadedSet {
        let file = QuestionSetFile(id: UUID().uuidString, name: name, importedAt: Date(), questions: questions)
        try writeSetFile(file)
        if !stats.isEmpty {
            writeStats(id: file.id, stats: stats)
        }
        let loaded = LoadedSet(id: file.id, name: name, importedAt: file.importedAt, questions: questions, stats: stats)
        sets.insert(loaded, at: 0)
        return loaded
    }

    func renameSet(id: String, name: String) {
        guard let idx = sets.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sets[idx].name = trimmed
        let set = sets[idx]
        try? writeSetFile(QuestionSetFile(id: set.id, name: set.name, importedAt: set.importedAt, questions: set.questions))
    }

    func duplicateSet(id: String) {
        guard let set = sets.first(where: { $0.id == id }) else { return }
        try? addSet(name: set.name + "のコピー", questions: set.questions, stats: set.stats)
    }

    /// 2つの問題集を合わせた新しい問題集を作る。元の2つはそのまま残す。
    /// 問題番号は重複を避けるため、先頭から 1,2,3… と振り直す（成績も番号に紐づくため）。
    func mergeSets(firstID: String, secondID: String) {
        guard let a = sets.first(where: { $0.id == firstID }),
              let b = sets.first(where: { $0.id == secondID }) else { return }
        let combined = (a.questions + b.questions).enumerated().map { idx, q in
            Question(number: idx + 1, front: q.front, back: q.back, explanation: q.explanation)
        }
        try? addSet(name: "\(a.name) + \(b.name)", questions: combined)
    }

    /// 問題の編集・削除を保存する。消えた番号の成績は破棄する。
    func updateQuestions(id: String, questions: [Question]) {
        guard let idx = sets.firstIndex(where: { $0.id == id }) else { return }
        sets[idx].questions = questions
        let numbers = Set(questions.map { $0.number })
        sets[idx].stats = sets[idx].stats.filter { numbers.contains($0.key) }
        let set = sets[idx]
        try? writeSetFile(QuestionSetFile(id: set.id, name: set.name, importedAt: set.importedAt, questions: set.questions))
        writeStats(id: id, stats: set.stats)
    }

    func deleteSet(id: String) {
        try? FileManager.default.removeItem(at: setFileURL(id: id))
        try? FileManager.default.removeItem(at: statsFileURL(id: id))
        sets.removeAll { $0.id == id }
    }

    func recordResult(setID: String, questionNumber: Int, correct: Bool) {
        guard let idx = sets.firstIndex(where: { $0.id == setID }) else { return }
        var stat = sets[idx].stats[questionNumber] ?? QuestionStat()
        if correct {
            stat.correctCount += 1
        } else {
            stat.wrongCount += 1
        }
        stat.lastCorrect = correct
        sets[idx].stats[questionNumber] = stat
        saveStats(setID: setID)
    }

    private func saveStats(setID: String) {
        guard let set = sets.first(where: { $0.id == setID }) else { return }
        if let data = try? JSONEncoder().encode(set.stats) {
            try? data.write(to: statsFileURL(id: setID), options: .atomic)
        }
    }
}

/// その問題への答え方。裏面が選択肢の記号そのものならタップで自動判定、
/// そうでなければ答えを見てから自己判定する。
enum AnswerMode {
    case choice(options: [String], correct: String)
    case reveal(correct: String)
}

func answerMode(for question: Question) -> AnswerMode {
    let back = question.back.trimmingCharacters(in: .whitespacesAndNewlines)
    let circled = ["①", "②", "③", "④", "⑤", "⑥"]
    if back.count == 1 && circled.contains(back) {
        let present = circled.filter { question.front.contains($0) }
        let options = present.isEmpty ? ["①", "②", "③", "④"] : present
        if options.contains(back) {
            return .choice(options: options, correct: back)
        }
    }
    if back == "○" || back == "×" {
        return .choice(options: ["○", "×"], correct: back)
    }
    return .reveal(correct: back)
}
