import SwiftUI
import Charts

/// 学習統計の画面。日ごとに「何問解いたか」を表示する。
/// 記録は設定がオンのときだけ行われる（デフォルトはオフ）。
struct StatsView: View {
    @AppStorage("seigoStatsEnabled") private var statsEnabled = false
    @State private var daily: [String: DayStat] = [:]

    private var sortedDays: [(key: String, stat: DayStat)] {
        daily.sorted { $0.key > $1.key }.map { (key: $0.key, stat: $0.value) }
    }

    private var totalAnswered: Int {
        daily.values.reduce(0) { $0 + $1.answered }
    }

    private var maxAnswered: Int {
        daily.values.map { $0.answered }.max() ?? 0
    }

    /// グラフ用：古い順に並べた直近14日分
    private var recentDays: [(key: String, stat: DayStat)] {
        Array(sortedDays.reversed().suffix(14))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("統計を取る", isOn: $statsEnabled)
                    Text("オンにすると、問題を解いた数が日ごとに記録されます。オフの間は記録されません。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if daily.isEmpty {
                    Section {
                        Text(statsEnabled ? "まだ記録がありません。問題を解くと、ここに日ごとの記録が出ます。" : "統計はオフです。オンにすると、その日から記録が始まります。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("合計") {
                        HStack {
                            Text("解いた問題数")
                            Spacer()
                            Text("\(totalAnswered)問")
                                .font(.headline)
                        }
                        HStack {
                            Text("記録した日数")
                            Spacer()
                            Text("\(daily.count)日")
                                .font(.headline)
                        }
                    }

                    Section("グラフ（直近14日）") {
                        Chart {
                            ForEach(recentDays, id: \.key) { item in
                                BarMark(
                                    x: .value("日付", date(fromKey: item.key) ?? Date()),
                                    y: .value("問題数", item.stat.answered)
                                )
                                .foregroundStyle(Color.accentColor)
                            }
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                                AxisValueLabel(format: .dateTime.month().day(), centered: true)
                            }
                        }
                        .frame(height: 180)
                    }

                    Section("日ごとの記録") {
                        ForEach(sortedDays, id: \.key) { item in
                            dayRow(key: item.key, stat: item.stat)
                        }
                    }
                }
            }
            .navigationTitle("統計")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                daily = DailyStats.load()
            }
        }
    }

    private func dayRow(key: String, stat: DayStat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(dateLabel(key))
                    .font(.headline)
                Spacer()
                Text("\(stat.answered)問")
                    .font(.headline)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentColor)
                        .frame(width: maxAnswered > 0 ? geo.size.width * CGFloat(stat.answered) / CGFloat(maxAnswered) : 0)
                }
            }
            .frame(height: 6)
            HStack(spacing: 12) {
                Text("正解 \(stat.correct)")
                    .foregroundStyle(.green)
                Text("不正解 \(stat.wrong)")
                    .foregroundStyle(.red)
                if stat.answered > 0 {
                    Text("正答率 \(Int(Double(stat.correct) / Double(stat.answered) * 100))%")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }

    private func date(fromKey key: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: key)
    }

    private func dateLabel(_ key: String) -> String {
        let inF = DateFormatter()
        inF.calendar = Calendar(identifier: .gregorian)
        inF.locale = Locale(identifier: "en_US_POSIX")
        inF.dateFormat = "yyyy-MM-dd"
        guard let date = inF.date(from: key) else { return key }
        let outF = DateFormatter()
        outF.calendar = Calendar(identifier: .gregorian)
        outF.locale = Locale(identifier: "ja_JP")
        outF.dateFormat = "M月d日（E）"
        let base = outF.string(from: date)
        if key == DailyStats.dayKey(for: Date()) {
            return "今日 ・ " + base
        }
        return base
    }
}
