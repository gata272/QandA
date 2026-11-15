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
                        ForEach(set.questions.sorted { $0.number < $1.number }) { q in
                            Button {
                                editing = q
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("No.\(q.number)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(q.front)
                                        .lineLimit(2)
                                        .foregroundStyle(.primary)
                                    Text("答え：\(q.back)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .onDelete { offsets in
                            delete(at: offsets, in: set)
                        }
                    } header: {
                        Text("タップで編集、左スワイプで削除（全\(set.questions.count)問）")
                    }
                }
            } else {
                ContentUnavailableView("問題集が見つかりません", systemImage: "questionmark.folder")
            }
        }
        .navigationTitle("問題一覧・編集")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { q in
            QuestionEditView(question: q) { updated in
                save(updated)
            }
        }
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
    var onSave: (Question) -> Void

    @State private var front: String
    @State private var back: String
    @State private var explanation: String
    @Environment(\.dismiss) private var dismiss

    init(question: Question, onSave: @escaping (Question) -> Void) {
        self.question = question
        self.onSave = onSave
        _front = State(initialValue: question.front)
        _back = State(initialValue: question.back)
        _explanation = State(initialValue: question.explanation)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("問題番号") {
                    Text("No.\(question.number)")
                        .foregroundStyle(.secondary)
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
                        onSave(Question(number: question.number, front: front, back: back, explanation: explanation))
                        dismiss()
                    }
                    .disabled(front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
