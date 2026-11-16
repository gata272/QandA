import Foundation

struct Question: Codable, Identifiable, Equatable {
    var number: Int
    var front: String
    var back: String
    var explanation: String
    var section: String? = nil
    var starred: Bool = false
    var id: Int { number }

    enum CodingKeys: String, CodingKey {
        case number, front, back, explanation, section, starred
    }

    init(number: Int, front: String, back: String, explanation: String, section: String? = nil, starred: Bool = false) {
        self.number = number
        self.front = front
        self.back = back
        self.explanation = explanation
        self.section = section
        self.starred = starred
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        number = try c.decode(Int.self, forKey: .number)
        front = try c.decode(String.self, forKey: .front)
        back = try c.decode(String.self, forKey: .back)
        explanation = try c.decode(String.self, forKey: .explanation)
        // v1.1以前のデータには無いキーがあるので、無ければ既定値にする
        section = try c.decodeIfPresent(String.self, forKey: .section)
        starred = try c.decodeIfPresent(Bool.self, forKey: .starred) ?? false
    }
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
    var sections: [String]

    enum CodingKeys: String, CodingKey {
        case id, name, importedAt, questions, sections
    }

    init(id: String, name: String, importedAt: Date, questions: [Question], sections: [String] = []) {
        self.id = id
        self.name = name
        self.importedAt = importedAt
        self.questions = questions
        self.sections = sections
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        importedAt = try c.decode(Date.self, forKey: .importedAt)
        questions = try c.decode([Question].self, forKey: .questions)
        // v1.1以前のファイルには無いので、無ければ空にする
        sections = try c.decodeIfPresent([String].self, forKey: .sections) ?? []
    }
}

struct LoadedSet: Identifiable {
    var id: String
    var name: String
    var importedAt: Date
    var questions: [Question]
    var sections: [String]
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
/// 複数リストから新しいリストを作るときの絞り込み
enum SetCombineFilter {
    case all
    case wrong
    case starred
}

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
            loaded.append(LoadedSet(id: file.id, name: file.name, importedAt: file.importedAt, questions: file.questions, sections: file.sections, stats: stats))
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

    /// 問題集ファイルと成績ファイルを、現在の内容で丸ごと書き直す
    private func persist(_ set: LoadedSet) {
        try? writeSetFile(QuestionSetFile(id: set.id, name: set.name, importedAt: set.importedAt, questions: set.questions, sections: set.sections))
        writeStats(id: set.id, stats: set.stats)
    }

    @discardableResult
    func addSet(name: String, questions: [Question], stats: [Int: QuestionStat] = [:], sections: [String] = []) throws -> LoadedSet {
        let file = QuestionSetFile(id: UUID().uuidString, name: name, importedAt: Date(), questions: questions, sections: sections)
        try writeSetFile(file)
        if !stats.isEmpty {
            writeStats(id: file.id, stats: stats)
        }
        let loaded = LoadedSet(id: file.id, name: name, importedAt: file.importedAt, questions: questions, sections: sections, stats: stats)
        sets.insert(loaded, at: 0)
        return loaded
    }

    func renameSet(id: String, name: String) {
        guard let idx = sets.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sets[idx].name = trimmed
        persist(sets[idx])
    }

    func duplicateSet(id: String) {
        guard let set = sets.first(where: { $0.id == id }) else { return }
        _ = try? addSet(name: set.name + "のコピー", questions: set.questions, stats: set.stats, sections: set.sections)
    }

    /// 2つの問題集を合わせた新しい問題集を作る。元の2つはそのまま残す。
    /// 問題番号は重複を避けるため、先頭から 1,2,3… と振り直す（成績も番号に紐づくため）。
    /// セクションは両方のものを引き継ぐ。
    func mergeSets(firstID: String, secondID: String) {
        guard let a = sets.first(where: { $0.id == firstID }),
              let b = sets.first(where: { $0.id == secondID }) else { return }
        var sections = a.sections
        for s in b.sections where !sections.contains(s) { sections.append(s) }
        let combined = (a.questions + b.questions).enumerated().map { idx, q in
            Question(number: idx + 1, front: q.front, back: q.back, explanation: q.explanation, section: q.section, starred: q.starred)
        }
        for q in combined { if let s = q.section, !sections.contains(s) { sections.append(s) } }
        _ = try? addSet(name: "\(a.name) + \(b.name)", questions: combined, sections: sections)
    }

    /// 複数の問題集から新しい問題集を作る。filter で「全部／間違いのみ／スター付きのみ」を選べる。
    /// 作った問題数を返す（0なら作っていない）。
    @discardableResult
    func createSetFromSets(ids: [String], filter: SetCombineFilter, name: String) -> Int {
        let chosen = ids.compactMap { id in sets.first { $0.id == id } }
        guard !chosen.isEmpty else { return 0 }
        var sections: [String] = []
        var raw: [Question] = []
        for set in chosen {
            for s in set.sections where !sections.contains(s) { sections.append(s) }
            let qs: [Question]
            switch filter {
            case .all:
                qs = set.questions
            case .wrong:
                qs = set.questions.filter { set.stats[$0.number]?.lastCorrect == false }
            case .starred:
                qs = set.questions.filter { $0.starred }
            }
            raw += qs
        }
        guard !raw.isEmpty else { return 0 }
        for q in raw { if let s = q.section, !sections.contains(s) { sections.append(s) } }
        let combined = raw.enumerated().map { idx, q in
            Question(number: idx + 1, front: q.front, back: q.back, explanation: q.explanation, section: q.section, starred: q.starred)
        }
        do {
            try addSet(name: name, questions: combined, sections: sections)
            return combined.count
        } catch {
            return 0
        }
    }

    // MARK: - セクション

    func addSection(setID: String, name: String) {
        guard let idx = sets.firstIndex(where: { $0.id == setID }) else { return }
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !sets[idx].sections.contains(t) else { return }
        sets[idx].sections.append(t)
        persist(sets[idx])
    }

    func renameSection(setID: String, old: String, new: String) {
        guard let idx = sets.firstIndex(where: { $0.id == setID }) else { return }
        let t = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t != old, !sets[idx].sections.contains(t) else { return }
        if let si = sets[idx].sections.firstIndex(of: old) {
            sets[idx].sections[si] = t
        }
        for qi in sets[idx].questions.indices where sets[idx].questions[qi].section == old {
            sets[idx].questions[qi].section = t
        }
        persist(sets[idx])
    }

    /// 番号の範囲でまとめてセクションへ割り当てる。
    func assignSectionRange(setID: String, section: String, from: Int, to: Int) {
        guard let idx = sets.firstIndex(where: { $0.id == setID }) else { return }
        guard sets[idx].sections.contains(section) else { return }
        let lo = min(from, to)
        let hi = max(from, to)
        for qi in sets[idx].questions.indices where (lo...hi).contains(sets[idx].questions[qi].number) {
            sets[idx].questions[qi].section = section
        }
        persist(sets[idx])
    }

    /// セクションを消す。そこに入っていた問題は「未分類」に戻る（問題自体は消えない）。
    func deleteSection(setID: String, name: String) {
        guard let idx = sets.firstIndex(where: { $0.id == setID }) else { return }
        sets[idx].sections.removeAll { $0 == name }
        for qi in sets[idx].questions.indices where sets[idx].questions[qi].section == name {
            sets[idx].questions[qi].section = nil
        }
        persist(sets[idx])
    }

    /// 問題の編集・削除を保存する。消えた番号の成績は破棄する。
    func updateQuestions(id: String, questions: [Question]) {
        guard let idx = sets.firstIndex(where: { $0.id == id }) else { return }
        sets[idx].questions = questions
        let numbers = Set(questions.map { $0.number })
        sets[idx].stats = sets[idx].stats.filter { numbers.contains($0.key) }
        persist(sets[idx])
    }

    func deleteSet(id: String) {
        try? FileManager.default.removeItem(at: setFileURL(id: id))
        try? FileManager.default.removeItem(at: statsFileURL(id: id))
        sets.removeAll { $0.id == id }
    }

    func setStar(setID: String, questionNumber: Int, starred: Bool) {
        guard let idx = sets.firstIndex(where: { $0.id == setID }) else { return }
        guard let qi = sets[idx].questions.firstIndex(where: { $0.number == questionNumber }) else { return }
        guard sets[idx].questions[qi].starred != starred else { return }
        sets[idx].questions[qi].starred = starred
        persist(sets[idx])
    }

    func toggleStar(setID: String, questionNumber: Int) {
        guard let set = sets.first(where: { $0.id == setID }),
              let q = set.questions.first(where: { $0.number == questionNumber }) else { return }
        setStar(setID: setID, questionNumber: questionNumber, starred: !q.starred)
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
