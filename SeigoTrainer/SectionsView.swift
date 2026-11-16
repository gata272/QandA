import SwiftUI

/// 問題集内のセクション（章分け）を作成・名前変更・削除する画面。
/// 問題の振り分けは「問題一覧・編集」で各問題を開いてセクションを選ぶ。
struct SectionListView: View {
    @ObservedObject var store: SetStore
    let setID: String

    @State private var newName = ""
    @State private var newStartText = ""
    @State private var newEndText = ""
    @State private var assignSectionName = ""
    @State private var assignStartText = ""
    @State private var assignEndText = ""
    @State private var renaming: String? = nil
    @State private var renameText = ""

    private var set: LoadedSet? {
        store.sets.first { $0.id == setID }
    }

    var body: some View {
        Group {
            if let set {
                List {
                    Section("新しいセクション") {
                        TextField("セクション名（例: 第1章）", text: $newName)
                        HStack {
                            Text("番号で割り当て（任意）")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            TextField("開始", text: $newStartText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 52)
                            Text("〜")
                            TextField("終了", text: $newEndText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 52)
                        }
                        Button("追加") {
                            let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                            store.addSection(setID: setID, name: name)
                            if let f = Int(newStartText), let t = Int(newEndText) {
                                store.assignSectionRange(setID: setID, section: name, from: f, to: t)
                            }
                            newName = ""
                            newStartText = ""
                            newEndText = ""
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || set.sections.contains(newName.trimmingCharacters(in: .whitespacesAndNewlines)))
                    }

                    Section("番号で割り当てる") {
                        if set.sections.isEmpty {
                            Text("先にセクションを作ってください")
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("セクション", selection: $assignSectionName) {
                                ForEach(set.sections, id: \.self) { name in
                                    Text(name).tag(name)
                                }
                            }
                            HStack {
                                Text("範囲")
                                Spacer()
                                TextField("開始", text: $assignStartText)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 52)
                                Text("〜")
                                TextField("終了", text: $assignEndText)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 52)
                            }
                            Button("この範囲を割り当てる") {
                                if let f = Int(assignStartText), let t = Int(assignEndText), !assignSectionName.isEmpty {
                                    store.assignSectionRange(setID: setID, section: assignSectionName, from: f, to: t)
                                }
                            }
                            .disabled(Int(assignStartText) == nil || Int(assignEndText) == nil || assignSectionName.isEmpty)
                            Text("この問題集は No.\(set.minNumber)〜\(set.maxNumber) です")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("セクション一覧") {
                        ForEach(set.sections, id: \.self) { name in
                            HStack {
                                Text(name)
                                Spacer()
                                Text("\(set.questions.filter { $0.section == name }.count)問")
                                    .foregroundStyle(.secondary)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    store.deleteSection(setID: setID, name: name)
                                } label: {
                                    Label("削除", systemImage: "trash")
                                }
                                Button {
                                    renaming = name
                                    renameText = name
                                } label: {
                                    Label("名前変更", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                        let unassigned = set.questions.filter { $0.section == nil || $0.section == "" }.count
                        if unassigned > 0 {
                            HStack {
                                Text("未分類")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(unassigned)問")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Section {
                        Text("問題をセクションへ振り分けるには、「問題一覧・編集」で問題を開き、セクションを選んでください。セクションを削除しても問題は消えず、未分類に戻ります。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ContentUnavailableView("問題集が見つかりません", systemImage: "questionmark.folder")
            }
        }
        .navigationTitle("セクションを管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            if assignSectionName.isEmpty {
                assignSectionName = set?.sections.first ?? ""
            }
        }
        .alert("名前を変更", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("セクション名", text: $renameText)
            Button("キャンセル", role: .cancel) { renaming = nil }
            Button("保存") {
                if let old = renaming {
                    store.renameSection(setID: setID, old: old, new: renameText)
                }
                renaming = nil
            }
        }
    }
}
