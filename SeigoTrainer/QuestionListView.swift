import SwiftUI

/// 問題集の中身を一覧し、1問ずつの編集（表面・裏面・解説）と削除ができる画面。
/// 問題番号は成績データのキーになっているため、ここでは変更しない。
struct QuestionListView: View {
    @ObservedObject var store: SetStore
    let setID: String

    @State private var editing: Question? = nil

    private var set: LoadedSet? {
        store.sets.first { $0.id == setID }
    }

    var body: some View {
        Group {
            if let set {
                List {
                    Section {
                        ForEach(sortedQuestions(set)) { q in
                            QuestionRowView(question: q, mastery: set.stats[q.number]?.mastery ?? 0) {
                                editing = q
                            } onToggleStar: {
                                store.toggleStar(setID: setID, questionNumber: q.number)
                            }
                        }
                        .onDelete { offsets in
                            delete(at: offsets, in: set)
                        }
                    } header: {
                        Text("タップで編集、右スワイプでスター、左スワイプで削除（全\(set.questions.count)問）")
                    }
                }
            } else {
                ContentUnavailableView("問題集が見つかりません", systemImage: "questionmark.folder")
            }
        }
        .navigationTitle("問題一覧・編集")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { q in
            QuestionEditView(question: q, sections: set?.sections ?? [], mastery: set?.stats[q.number]?.mastery ?? 0) { updated, newMastery in
                save(updated)
                store.setMastery(setID: setID, questionNumber: updated.number, mastery: newMastery)
            }
        }
    }

    private func sortedQuestions(_ set: LoadedSet) -> [Question] {
        set.questions.sorted { $0.number < $1.number }
    }

    private func delete(at offsets: IndexSet, in set: LoadedSet) {
        let sorted = set.questions.sorted { $0.number < $1.number }
        let removing = Set(offsets.map { sorted[$0].number })
        let remaining = set.questions.filter { !removing.contains($0.number) }
        store.updateQuestions(id: setID, questions: remaining)
    }

    private func save(_ updated: Question) {
        guard let set else { return }
        var questions = set.questions
        if let idx = questions.firstIndex(where: { $0.number == updated.number }) {
            questions[idx] = updated
            store.updateQuestions(id: setID, questions: questions)
        }
    }
}

private struct QuestionEditView: View {
    let question: Question
    let sections: [String]
    var onSave: (Question, Int) -> Void

    @State private var front: String
    @State private var back: String
    @State private var explanation: String
    @State private var sectionName: String
    @State private var starred: Bool
    @State private var mastery: Int
    @Environment(\.dismiss) private var dismiss

    init(question: Question, sections: [String], mastery: Int, onSave: @escaping (Question, Int) -> Void) {
        self.question = question
        self.sections = sections
        self.onSave = onSave
        _front = State(initialValue: question.front)
        _back = State(initialValue: question.back)
        _explanation = State(initialValue: question.explanation)
        _sectionName = State(initialValue: question.section ?? "")
        _starred = State(initialValue: question.starred)
        _mastery = State(initialValue: mastery)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("問題番号") {
                    Text("No.\(question.number)")
                        .foregroundStyle(.secondary)
                }
                Section {
                    Toggle("スターを付ける", isOn: $starred)
                }
                Section("状態") {
                    HStack(spacing: 10) {
                        masteryButton(title: "覚えた", value: 1, color: .green)
                        masteryButton(title: "覚えてない", value: 2, color: .orange)
                    }
                    Text("現在：\(masteryName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !sections.isEmpty {
                    Section("セクション") {
                        Picker("セクション", selection: $sectionName) {
                            Text("未分類").tag("")
                            ForEach(sections, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                    }
                }
                Section("表面（問題）") {
                    TextField("表面", text: $front, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section("裏面（答え）") {
                    TextField("裏面", text: $back, axis: .vertical)
                        .lineLimit(1...4)
                }
                Section("解説") {
                    TextField("解説", text: $explanation, axis: .vertical)
                        .lineLimit(3...10)
                }
            }
            .navigationTitle("問題を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(Question(number: question.number, front: front, back: back, explanation: explanation, section: sectionName.isEmpty ? nil : sectionName, starred: starred), mastery)
                        dismiss()
                    }
                    .disabled(front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var masteryName: String {
        switch mastery {
        case 1: return "覚えた"
        case 2: return "覚えてない"
        default: return "なし"
        }
    }

    /// 状態ボタン。「なし」のときだけその状態になり、同じ状態や反対の状態のときは「なし」に戻る。
    private func masteryButton(title: String, value: Int, color: Color) -> some View {
        let selected = mastery == value
        return Button {
            mastery = (mastery == 0) ? value : 0
        } label: {
            HStack(spacing: 4) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                }
                Text(title)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .tint(color)
    }
}

/// 問題一覧の1行分。コンパイラの型チェックを軽くするため、行は独立したビューに分けている。
private struct QuestionRowView: View {
    let question: Question
    let mastery: Int
    var onTap: () -> Void
    var onToggleStar: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("No.\(question.number)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if question.starred {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                    if mastery == 1 {
                        Text("覚えた")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.green)
                    } else if mastery == 2 {
                        Text("覚えてない")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.orange)
                    }
                }
                Text(question.front)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                Text("答え：\(question.back)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let sec = question.section, !sec.isEmpty {
                    Text("セクション：\(sec)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .swipeActions(edge: .leading) {
            Button(action: onToggleStar) {
                Label(question.starred ? "スターを外す" : "スター", systemImage: "star")
            }
            .tint(.yellow)
        }
    }
}
