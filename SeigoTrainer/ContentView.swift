import SwiftUI

struct ContentView: View {
    @StateObject private var store = SetStore()
    @State private var showPicker = false
    @State private var importError: String? = nil
    @State private var importNotice: String? = nil
    @State private var isImporting = false
    @State private var activeSheet: ActiveSheet? = nil
    @State private var renameText = ""
    @State private var editMode: EditMode = .inactive
    @State private var selectedIDs: Set<String> = []

    private enum ActiveSheet: Identifiable {
        case rename(LoadedSet)
        case merge(LoadedSet)

        var id: String {
            switch self {
            case .rename(let set): return "rename-" + set.id
            case .merge(let set): return "merge-" + set.id
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.sets.isEmpty {
                    ContentUnavailableView {
                        Label("問題集がありません", systemImage: "books.vertical")
                    } description: {
                        Text("CSVファイル（番号,表面,裏面,解説）、またはCSV入りのZIPを読み込むと、アプリ内に保存されます")
                    } actions: {
                        Button {
                            showPicker = true
                        } label: {
                            Text("CSV / ZIPを読み込む")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List(selection: $selectedIDs) {
                        ForEach(store.sets) { set in
                            NavigationLink {
                                SetupView(store: store, setID: set.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(set.name)
                                        .font(.headline)
                                        .lineLimit(1)
                                    HStack(spacing: 10) {
                                        Text("全\(set.questions.count)問")
                                        if set.wrongRemaining > 0 {
                                            Text("間違い残り \(set.wrongRemaining)問")
                                                .foregroundStyle(.red)
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .tag(set.id)
                            .contextMenu {
                                Button {
                                    renameText = set.name
                                    activeSheet = .rename(set)
                                } label: {
                                    Label("名前を変更", systemImage: "pencil")
                                }
                                Button {
                                    store.duplicateSet(id: set.id)
                                } label: {
                                    Label("複製する", systemImage: "doc.on.doc")
                                }
                                if store.sets.count >= 2 {
                                    Button {
                                        activeSheet = .merge(set)
                                    } label: {
                                        Label("他の問題集と合わせる", systemImage: "square.stack.3d.up")
                                    }
                                }
                                Button(role: .destructive) {
                                    store.deleteSet(id: set.id)
                                } label: {
                                    Label("削除", systemImage: "trash")
                                }
                            }
                        }
                        .onDelete { offsets in
                            for i in offsets {
                                store.deleteSet(id: store.sets[i].id)
                            }
                        }
                    }
                    .sheet(item: $activeSheet) { sheet in
                        switch sheet {
                        case .rename(let set):
                            renameView(set)
                        case .merge(let set):
                            mergeView(set)
                        }
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !store.sets.isEmpty {
                        Button(editMode == .active ? "完了" : "選択") {
                            if editMode == .active {
                                editMode = .inactive
                                selectedIDs = []
                            } else {
                                editMode = .active
                            }
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showPicker = true
                    } label: {
                        Label("読み込む", systemImage: "plus")
                    }
                }
                if editMode == .active {
                    ToolbarItem(placement: .bottomBar) {
                        HStack {
                            Text("\(selectedIDs.count)件選択中")
                                .font(.subheadline)
                            Spacer()
                            Button("全部で作る") { createCombined(filter: .all) }
                                .disabled(selectedIDs.isEmpty)
                            Button("間違いだけ") { createCombined(filter: .wrong) }
                                .disabled(selectedIDs.isEmpty)
                            Button("スターだけ") { createCombined(filter: .starred) }
                                .disabled(selectedIDs.isEmpty)
                        }
                    }
                }
            }
            .sheet(isPresented: $showPicker) {
                DocumentPicker { url in
                    showPicker = false
                    importFile(url)
                } onCancel: {
                    showPicker = false
                }
            }
            .overlay {
                if isImporting {
                    ZStack {
                        Color.black.opacity(0.2).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("読み込み中…")
                                .font(.callout)
                        }
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .alert("読み込めませんでした", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
            .alert("お知らせ", isPresented: Binding(
                get: { importNotice != nil },
                set: { if !$0 { importNotice = nil } }
            )) {
                Button("OK") { importNotice = nil }
            } message: {
                Text(importNotice ?? "")
            }
        }
    }

    // MARK: - 名前変更

    private func renameView(_ set: LoadedSet) -> some View {
        NavigationStack {
            Form {
                Section("問題集の名前") {
                    TextField("名前", text: $renameText)
                }
                Section {
                    Text("元の名前: \(set.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("名前を変更")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { activeSheet = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        store.renameSet(id: set.id, name: renameText)
                        activeSheet = nil
                    }
                    .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    // MARK: - マージ

    private func mergeView(_ source: LoadedSet) -> some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.sets.filter { $0.id != source.id }) { other in
                        Button {
                            store.mergeSets(firstID: source.id, secondID: other.id)
                            activeSheet = nil
                            importNotice = "「\(source.name)」と「\(other.name)」を合わせた新しい問題集を作りました。元の2つはそのまま残っています（問題番号は先頭から振り直しました）"
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(other.name)
                                        .foregroundStyle(.primary)
                                    Text("全\(other.questions.count)問")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                } header: {
                    Text("「\(source.name)」（\(source.questions.count)問）と合わせる相手")
                } footer: {
                    Text("合わせると合計 \(source.questions.count) 問＋相手の問題数の、新しい問題集ができます。")
                }
            }
            .navigationTitle("問題集を合わせる")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { activeSheet = nil }
                }
            }
        }
    }

    // MARK: - 読み込み

    private func importFile(_ url: URL) {
        isImporting = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = try Data(contentsOf: url)
                let head = [UInt8](data.prefix(2))
                let isZip = url.pathExtension.lowercased() == "zip" || head == [0x50, 0x4B]
                if isZip {
                    let result = try ZipImporter.extractQuestionSets(data: data)
                    DispatchQueue.main.async {
                        finishZipImport(result: result)
                    }
                } else {
                    let questions = try CSVParser.parse(data: data)
                    let name = url.deletingPathExtension().lastPathComponent
                    DispatchQueue.main.async {
                        do {
                            try store.addSet(name: name, questions: questions)
                            importNotice = "「\(name)」（\(questions.count)問）を追加しました"
                        } catch {
                            importError = error.localizedDescription
                        }
                        isImporting = false
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    importError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    isImporting = false
                }
            }
        }
    }

    private func finishZipImport(result: (sets: [(name: String, questions: [Question])],
                                           failures: [(name: String, message: String)])) {
        var added: [(name: String, count: Int)] = []
        for item in result.sets {
            do {
                try store.addSet(name: item.name, questions: item.questions)
                added.append((name: item.name, count: item.questions.count))
            } catch {
                // 保存に失敗したものは失敗扱いにする
            }
        }
        var parts: [String] = []
        if added.count == 1 {
            parts.append("「\(added[0].name)」（\(added[0].count)問）を追加しました")
        } else if added.count > 1 {
            parts.append("\(added.count)件の問題集（合計\(added.reduce(0) { $0 + $1.count })問）を追加しました")
        }
        if !result.failures.isEmpty {
            parts.append("読めなかったファイル: " + result.failures.map { $0.name }.joined(separator: "、"))
        }
        if added.isEmpty {
            importError = result.failures.first?.message ?? "読み込めませんでした"
        } else {
            importNotice = parts.joined(separator: "\n")
        }
        isImporting = false
    }

    // MARK: - 複数選択から新規リスト

    private func createCombined(filter: SetCombineFilter) {
        let ids = store.sets.map { $0.id }.filter { selectedIDs.contains($0) }
        let name: String
        let emptyMessage: String
        switch filter {
        case .all:
            name = "まとめ（\(ids.count)件）"
            emptyMessage = "選択した問題集に問題がないため、リストは作りませんでした"
        case .wrong:
            name = "間違いまとめ（\(ids.count)件）"
            emptyMessage = "選択した問題集に、間違えた問題がまだないため、リストは作りませんでした"
        case .starred:
            name = "スターまとめ（\(ids.count)件）"
            emptyMessage = "選択した問題集に、スター付きの問題がまだないため、リストは作りませんでした"
        }
        let count = store.createSetFromSets(ids: ids, filter: filter, name: name)
        editMode = .inactive
        selectedIDs = []
        importNotice = count > 0
            ? "新しい問題集「\(name)」（\(count)問）を作りました"
            : emptyMessage
    }

}
