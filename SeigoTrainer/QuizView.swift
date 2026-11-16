import SwiftUI

struct QuizView: View {
    @ObservedObject var store: SetStore
    let setID: String

    @State private var session: [Question]
    @State private var index = 0
    @State private var graded = false
    @State private var picked: String? = nil
    @State private var currentCorrect: Bool? = nil
    @State private var results: [Int: Bool] = [:]
    @State private var finished = false
    @State private var starredNumbers: Set<Int>
    @Environment(\.dismiss) private var dismiss

    init(store: SetStore, setID: String, questions: [Question]) {
        _store = ObservedObject(wrappedValue: store)
        self.setID = setID
        _session = State(initialValue: questions)
        _starredNumbers = State(initialValue: Set(questions.filter { $0.starred }.map { $0.number }))
    }

    private var current: Question? {
        session.indices.contains(index) ? session[index] : nil
    }

    private var setName: String {
        store.sets.first { $0.id == setID }?.name ?? "出題中"
    }

    var body: some View {
        Group {
            if finished {
                resultsView
            } else if let q = current {
                quizView(q)
            } else {
                ContentUnavailableView("問題がありません", systemImage: "questionmark.circle")
            }
        }
        .navigationTitle(setName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - 出題画面

    private func quizView(_ q: Question) -> some View {
        let mode = answerMode(for: q)
        return VStack(spacing: 0) {
            HStack {
                Text("No.\(q.number)")
                    .font(.headline)
                Text(scoreText(currentScore(for: q)))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(scoreColor(currentScore(for: q)))
                Spacer()
                Text("\(index + 1) / \(session.count)")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            ProgressView(value: Double(results.count), total: Double(max(session.count, 1)))
                .padding(.horizontal)
                .padding(.vertical, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(q.front)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if graded {
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            if let ok = currentCorrect {
                                Label(ok ? "正解！" : "不正解", systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .font(.headline)
                                    .foregroundStyle(ok ? Color.green : Color.red)
                                Text("正解：\(q.back)")
                                    .font(.headline)
                            } else {
                                Text("答え：\(q.back)")
                                    .font(.headline)
                            }
                            if !q.explanation.isEmpty {
                                Text(q.explanation)
                                    .font(.callout)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }

            bottomBar(q, mode: mode)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if abs(value.translation.height) < 50 {
                        if value.translation.width > 80 {
                            // 左から右へのスワイプで前の問題に戻る
                            goBack()
                        } else if value.translation.width < -80 {
                            // 右から左へのスワイプで、解説を見ずに次の問題へ進む
                            next()
                        }
                    }
                }
        )
    }

    @ViewBuilder
    private func bottomBar(_ q: Question, mode: AnswerMode) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Spacer()
                Button {
                    toggleStar(q)
                } label: {
                    Image(systemName: starredNumbers.contains(q.number) ? "star.fill" : "star")
                        .font(.title2)
                        .foregroundStyle(starredNumbers.contains(q.number) ? Color.yellow : .secondary)
                        .symbolEffect(.bounce, value: starredNumbers.contains(q.number))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button("やめる") { dismiss() }
                    .buttonStyle(.bordered)
            }
            switch mode {
            case .choice(let options, let correct):
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76))], spacing: 10) {
                    ForEach(options, id: \.self) { opt in
                        optionButton(opt, correct: correct, question: q)
                    }
                }
                if graded {
                    Button {
                        next()
                    } label: {
                        Text(index + 1 < session.count ? "次の問題へ" : "結果を見る")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        skipAndReveal()
                    } label: {
                        Text("スキップ")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                }
            case .reveal:
                if !graded {
                    Button {
                        graded = true
                    } label: {
                        Text("答えと解説を見る")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    HStack(spacing: 10) {
                        Button {
                            selfGrade(false, question: q)
                        } label: {
                            Text("不正解")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)

                        Button {
                            skip()
                        } label: {
                            Text("スキップ")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            selfGrade(true, question: q)
                        } label: {
                            Text("正解")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }
                }
            }
        }
        .padding()
        .background(.bar)
    }

    private func optionButton(_ opt: String, correct: String, question: Question) -> some View {
        let isCorrect = opt == correct
        let isPicked = opt == picked
        var bg: Color = Color(.secondarySystemBackground)
        var fg: Color = .primary
        if graded {
            if isCorrect {
                bg = .green
                fg = .white
            } else if isPicked {
                bg = .red
                fg = .white
            }
        }
        return Button {
            if !graded {
                pick(opt, correct: correct, question: question)
            }
        } label: {
            Text(opt)
                .font(.title2)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(bg, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(fg)
        }
        .disabled(graded)
    }

    // MARK: - 判定と進行

    /// その問題の現在の値（成績データから読む。回答すると即座に増減する）
    private func currentScore(for q: Question) -> Int {
        store.sets.first { $0.id == setID }?.stats[q.number]?.score ?? 0
    }

    private func scoreText(_ v: Int) -> String {
        v > 0 ? "+\(v)" : "\(v)"
    }

    private func scoreColor(_ v: Int) -> Color {
        if v > 0 { return .green }
        if v < 0 { return .red }
        return .secondary
    }

    private func toggleStar(_ q: Question) {
        let now = !starredNumbers.contains(q.number)
        if now {
            starredNumbers.insert(q.number)
        } else {
            starredNumbers.remove(q.number)
        }
        store.setStar(setID: setID, questionNumber: q.number, starred: now)
    }

    private func pick(_ opt: String, correct: String, question: Question) {
        picked = opt
        let ok = opt == correct
        currentCorrect = ok
        graded = true
        results[question.number] = ok
        store.recordResult(setID: setID, questionNumber: question.number, correct: ok)
    }

    private func selfGrade(_ ok: Bool, question: Question) {
        currentCorrect = ok
        results[question.number] = ok
        store.recordResult(setID: setID, questionNumber: question.number, correct: ok)
        next()
    }

    /// 選択式でスキップしたとき: 結果は記録せず、解答と解説だけを表示する
    private func skipAndReveal() {
        graded = true
    }

    /// 結果を記録せずに次へ進む（最後の問題なら結果画面へ）
    private func skip() {
        next()
    }

    /// 前の問題に戻る。戻った問題は、回答済みでも常に問題画面（未回答の表示）で開く。
    /// 以前の回答の記録自体は残り、解き直すと上書きされる。
    private func goBack() {
        guard index > 0 else { return }
        index -= 1
        graded = false
        picked = nil
        currentCorrect = nil
    }

    private func next() {
        if index + 1 < session.count {
            index += 1
            graded = false
            picked = nil
            currentCorrect = nil
        } else {
            finished = true
        }
    }

    // MARK: - 結果画面

    private var resultsView: some View {
        let total = results.count
        let correctCount = results.values.filter { $0 }.count
        let wrong = session.filter { results[$0.number] == false }
        return List {
            Section {
                VStack(spacing: 6) {
                    Text("\(correctCount) / \(total) 問正解")
                        .font(.title2)
                        .fontWeight(.bold)
                    if total > 0 {
                        Text("正答率 \(Int(Double(correctCount) / Double(total) * 100))%")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            if !wrong.isEmpty {
                Section("間違えた問題（\(wrong.count)問）") {
                    ForEach(wrong) { q in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Text("No.\(q.number)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if starredNumbers.contains(q.number) {
                                    Image(systemName: "star.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.yellow)
                                }
                            }
                            Text(q.front)
                                .lineLimit(2)
                            Text("正解：\(q.back)")
                                .font(.callout)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }

            Section {
                if !wrong.isEmpty {
                    Button("間違えた問題だけもう一度") {
                        retryWrong(wrong)
                    }
                }
                Button("終わる") { dismiss() }
            }
        }
    }

    private func retryWrong(_ wrong: [Question]) {
        session = wrong
        index = 0
        results = [:]
        graded = false
        picked = nil
        currentCorrect = nil
        finished = false
    }
}
