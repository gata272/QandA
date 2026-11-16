import SwiftUI

struct SetupView: View {
    @ObservedObject var store: SetStore
    let setID: String

    @State private var starOnly = false // スター付きのみに絞る
    @State private var wrongOnly = false // 間違いのみ（値がマイナス）に絞る
    @State private var startNumber = 1
    @State private var endNumber = 40
    @AppStorage("seigoShuffle") private var shuffle = false
    @State private var sectionFilter = "" // "" = すべて, "__unassigned__" = 未分類, それ以外はセクション名
    @State private var sectionExpanded = false // セクション絞り込みは閉じた状態が既定
    @State private var rangeExpanded = false // 数字の範囲指定は閉じた状態が既定
    @State private var startQuiz = false
    @State private var didInitRange = false
    @State private var screenMode = 0 // 0: 出題モード, 1: 編集モード（開いた直後は常に出題モード）

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
        // 絞り込みは全部を重ねて適用する（セクション・範囲・スター・間違い）
        var qs = set.questions.filter { matchesSection($0) }
        qs = qs.filter { $0.number >= startNumber && $0.number <= endNumber }
        if starOnly {
            qs = qs.filter { $0.starred }
        }
        if wrongOnly {
            qs = qs.filter { (set.stats[$0.number]?.score ?? 0) < 0 }
        }
        qs.sort { $0.number < $1.number }
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
                        Picker("モード", selection: $screenMode) {
                            Text("出題モード").tag(0)
                            Text("編集モード").tag(1)
                        }
                        .pickerStyle(.segmented)
                    }

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
                            if set.starredCount > 0 {
                                Text("スター \(set.starredCount)問")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }

                    if screenMode == 0 {
                    Section("絞り込み") {
                        Toggle("スター付きのみ", isOn: $starOnly)
                        Toggle("間違いのみ（値がマイナス）", isOn: $wrongOnly)
                        if starOnly && !set.questions.contains(where: { $0.starred && matchesSection($0) }) {
                            Text("スター付きの問題はまだありません")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if wrongOnly && !set.questions.contains(where: { matchesSection($0) && (set.stats[$0.number]?.score ?? 0) < 0 }) {
                            Text("間違えた問題（値がマイナス）はまだありません")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !set.sections.isEmpty {
                        Section {
                            DisclosureGroup(isExpanded: $sectionExpanded) {
                                Picker("セクション", selection: $sectionFilter) {
                                    Text("すべて").tag("")
                                    ForEach(set.sections, id: \.self) { name in
                                        Text(name).tag(name)
                                    }
                                    if set.questions.contains(where: { $0.section == nil || $0.section == "" }) {
                                        Text("未分類").tag("__unassigned__")
                                    }
                                }
                                .pickerStyle(.inline)
                            } label: {
                                HStack {
                                    Text("セクションで絞り込む")
                                    Spacer()
                                    Text(sectionFilter.isEmpty ? "すべて" : (sectionFilter == "__unassigned__" ? "未分類" : sectionFilter))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Section {
                        DisclosureGroup(isExpanded: $rangeExpanded) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("開始")
                                    Spacer()
                                    Text("No.")
                                        .foregroundStyle(.secondary)
                                    TextField("開始", value: $startNumber, format: .number)
                                        .keyboardType(.numberPad)
                                        .multilineTextAlignment(.trailing)
                                        .frame(width: 64)
                                    Stepper("", value: $startNumber, in: set.minNumber...set.maxNumber)
                                        .labelsHidden()
                                }
                                if set.minNumber < set.maxNumber {
                                    Slider(value: Binding(
                                        get: { Double(startNumber) },
                                        set: { startNumber = Int($0.rounded()) }
                                    ), in: Double(set.minNumber)...Double(set.maxNumber), step: 1)
                                }
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("終了")
                                    Spacer()
                                    Text("No.")
                                        .foregroundStyle(.secondary)
                                    TextField("終了", value: $endNumber, format: .number)
                                        .keyboardType(.numberPad)
                                        .multilineTextAlignment(.trailing)
                                        .frame(width: 64)
                                    Stepper("", value: $endNumber, in: set.minNumber...set.maxNumber)
                                        .labelsHidden()
                                }
                                if set.minNumber < set.maxNumber {
                                    Slider(value: Binding(
                                        get: { Double(endNumber) },
                                        set: { endNumber = Int($0.rounded()) }
                                    ), in: Double(set.minNumber)...Double(set.maxNumber), step: 1)
                                }
                            }
                            } label: {
                                HStack {
                                    Text("範囲（問題番号）")
                                    Spacer()
                                    Text("No.\(startNumber)〜\(endNumber)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onChange(of: startNumber) { _, v in
                            let clamped = min(max(v, set.minNumber), set.maxNumber)
                            if clamped != v { startNumber = clamped }
                            if startNumber > endNumber { endNumber = startNumber }
                        }
                        .onChange(of: endNumber) { _, v in
                            let clamped = min(max(v, set.minNumber), set.maxNumber)
                            if clamped != v { endNumber = clamped }
                            if endNumber < startNumber { startNumber = endNumber }
                        }

                    Section {
                        Toggle("ランダムに並べ替える", isOn: $shuffle)
                    }

                    Section {
                        NavigationLink {
                            ScopedQuestionListView(questions: selectedQuestions, stats: set.stats)
                        } label: {
                            Label("対象の問題一覧（\(selectedQuestions.count)問）", systemImage: "list.number")
                        }
                        .disabled(selectedQuestions.isEmpty)
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

                    if screenMode == 1 {
                        Section("編集") {
                            NavigationLink {
                                QuestionListView(store: store, setID: setID)
                            } label: {
                                Label("問題一覧・編集", systemImage: "list.bullet.rectangle")
                            }
                            NavigationLink {
                                SectionListView(store: store, setID: setID)
                            } label: {
                                Label("セクションを管理", systemImage: "folder.badge.gearshape")
                            }
                        }
                    }
                }
                .listSectionSpacing(.compact)
                .onAppear {
                    if !didInitRange {
                        didInitRange = true
                        startNumber = set.minNumber
                        endNumber = set.maxNumber
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: screenMode)
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

/// 現在の出題条件（モード・セクション・範囲）に合う問題の一覧（確認用）
struct ScopedQuestionListView: View {
    let questions: [Question]
    let stats: [Int: QuestionStat]

    var body: some View {
        List {
            Section {
                ForEach(questions) { q in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text("No.\(q.number)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let sc = stats[q.number]?.score {
                                Text(sc > 0 ? "+\(sc)" : "\(sc)")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(sc > 0 ? Color.green : (sc < 0 ? Color.red : Color.secondary))
                            }
                            if q.starred {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.yellow)
                            }
                            if let sec = q.section, !sec.isEmpty {
                                Text(sec)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(q.front)
                            .lineLimit(2)
                    }
                }
            } header: {
                Text("全\(questions.count)問")
            }
        }
        .navigationTitle("対象の問題一覧")
        .navigationBarTitleDisplayMode(.inline)
    }
}
