import SwiftUI

struct SetupView: View {
    @ObservedObject var store: SetStore
    let setID: String

    @State private var mode = 0 // 0: 範囲指定, 1: 全問, 2: 間違えた問題だけ
    @State private var startNumber = 1
    @State private var endNumber = 40
    @AppStorage("seigoShuffle") private var shuffle = false
    @State private var sectionFilter = "" // "" = すべて, "__unassigned__" = 未分類, それ以外はセクション名
    @State private var startQuiz = false
    @State private var didInitRange = false

    private var set: LoadedSet? {
        store.sets.first { $0.id == setID }
    }

    private func matchesSection(_ q: Question) -> Bool {
        switch sectionFilter {
        case "":
            return true
        case "__unassigned__":
            return q.section == nil || q.section == ""
        default:
            return q.section == sectionFilter
        }
    }

    private var selectedQuestions: [Question] {
        guard let set else { return [] }
        let base = set.questions.filter { matchesSection($0) }
        var qs: [Question]
        switch mode {
        case 1:
            qs = base.sorted { $0.number < $1.number }
        case 2:
            qs = base
                .filter { set.stats[$0.number]?.lastCorrect == false }
                .sorted { $0.number < $1.number }
        default:
            qs = base
                .filter { $0.number >= startNumber && $0.number <= endNumber }
                .sorted { $0.number < $1.number }
        }
        if shuffle {
            qs.shuffle()
        }
        return qs
    }

    var body: some View {
        Group {
            if let set {
                Form {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(set.name).font(.headline)
                            Text("全\(set.questions.count)問（No.\(set.minNumber)〜\(set.maxNumber)）")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if set.wrongRemaining > 0 {
                                Text("間違い残り \(set.wrongRemaining)問")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    Section("出題モード") {
                        Picker("出題モード", selection: $mode) {
                            Text("範囲指定").tag(0)
                            Text("全問").tag(1)
                            Text("間違いのみ").tag(2)
                        }
                        .pickerStyle(.segmented)
                        if mode == 2 && set.wrongRemaining == 0 {
                            Text("間違えた問題はまだありません")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section {
                        NavigationLink {
                            QuestionListView(store: store, setID: setID)
                        } label: {
                            Label("問題一覧・編集", systemImage: "list.bullet.rectangle")
                        }
                    }

                    if !set.sections.isEmpty {
                        Section("セクションで絞り込む") {
                            Picker("セクション", selection: $sectionFilter) {
                                Text("すべて").tag("")
                                ForEach(set.sections, id: \.self) { name in
                                    Text(name).tag(name)
                                }
                                if set.questions.contains(where: { $0.section == nil || $0.section == "" }) {
                                    Text("未分類").tag("__unassigned__")
                                }
                            }
                        }
                    }

                    Section {
                        NavigationLink {
                            SectionListView(store: store, setID: setID)
                        } label: {
                            Label("セクションを管理", systemImage: "folder.badge.gearshape")
                        }
                    }

                    if mode == 0 {
                        Section("範囲（問題番号）") {
                            Stepper(value: $startNumber, in: set.minNumber...set.maxNumber) {
                                HStack {
                                    Text("開始")
                                    Spacer()
                                    Text("No.\(startNumber)").foregroundStyle(.secondary)
                                }
                            }
                            Stepper(value: $endNumber, in: set.minNumber...set.maxNumber) {
                                HStack {
                                    Text("終了")
                                    Spacer()
                                    Text("No.\(endNumber)").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Section {
                        Toggle("ランダムに並べ替える", isOn: $shuffle)
                    }

                    Section {
                        Button {
                            startQuiz = true
                        } label: {
                            HStack {
                                Spacer()
                                Text("スタート（\(selectedQuestions.count)問）")
                                    .font(.headline)
                                Spacer()
                            }
                        }
                        .disabled(selectedQuestions.isEmpty)
                    }
                }
                .onAppear {
                    if !didInitRange {
                        didInitRange = true
                        startNumber = set.minNumber
                        endNumber = min(set.minNumber + 39, set.maxNumber)
                    }
                }
                .navigationDestination(isPresented: $startQuiz) {
                    QuizView(store: store, setID: setID, questions: selectedQuestions)
                }
            } else {
                ContentUnavailableView("問題集が見つかりません", systemImage: "questionmark.folder")
            }
        }
        .navigationTitle("出題設定")
        .navigationBarTitleDisplayMode(.inline)
    }
}
