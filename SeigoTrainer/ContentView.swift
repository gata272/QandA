import SwiftUI

struct ContentView: View {
    @StateObject private var store = SetStore()
    @State private var showPicker = false
    @State private var importError: String? = nil
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            Group {
                if store.sets.isEmpty {
                    ContentUnavailableView {
                        Label("問題集がありません", systemImage: "books.vertical")
                    } description: {
                        Text("CSVファイル（番号,表面,裏面,解説）を読み込むと、アプリ内に保存されます")
                    } actions: {
                        Button {
                            showPicker = true
                        } label: {
                            Text("CSVを読み込む")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
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
                        }
                        .onDelete { offsets in
                            for i in offsets {
                                store.deleteSet(id: store.sets[i].id)
                            }
                        }
                    }
                }
            }
            .navigationTitle("正誤トレーナー")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showPicker = true
                    } label: {
                        Label("読み込む", systemImage: "plus")
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
        }
    }

    private func importFile(_ url: URL) {
        isImporting = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = try Data(contentsOf: url)
                let questions = try CSVParser.parse(data: data)
                let name = url.deletingPathExtension().lastPathComponent
                DispatchQueue.main.async {
                    do {
                        try store.addSet(name: name, questions: questions)
                    } catch {
                        importError = error.localizedDescription
                    }
                    isImporting = false
                }
            } catch {
                DispatchQueue.main.async {
                    importError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    isImporting = false
                }
            }
        }
    }
}
