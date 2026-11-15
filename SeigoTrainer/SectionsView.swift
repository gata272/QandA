import SwiftUI

/// 問題集内のセクション（章分け）を作成・名前変更・削除する画面。
/// 問題の振り分けは「問題一覧・編集」で各問題を開いてセクションを選ぶ。
struct SectionListView: View {
    @ObservedObject var store: SetStore
    let setID: String

    @State private var newName = ""
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
                        HStack {
                            TextField("セクション名（例: 第1章）", text: $newName)
                            Button("追加") {
                                store.addSection(setID: setID, name: newName)
                                newName = ""
                            }
                            .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                      || set.sections.contains(newName.trimmingCharacters(in: .whitespacesAndNewlines)))
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
