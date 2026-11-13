import SwiftUI

/// 累计统计面板
struct StatsSheet: View {
    @ObservedObject var stats: StatsStoreWrapper
    @Environment(\.dismiss) private var dismiss

    private let attitudeLabel: [String: String] = [
        "positive": "看好", "neutral": "中立", "negative": "不看好", "mixed": "随机",
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 14) {
                    HStack(spacing: 8) {
                        kpi("累计份数", "\(stats.store.total) 份")
                        kpi("总用时", stats.store.durationText())
                        kpi("平均每份", String(format: "%.1f 秒", stats.store.averageSeconds))
                        kpi("成功率", "\(stats.store.successRate)%")
                    }

                    card("答题倾向分布") {
                        let att = stats.store.attitude
                        let keys = ["positive", "neutral", "negative", "mixed"].filter { (att[$0] ?? 0) > 0 }
                        if keys.isEmpty {
                            Text("暂无数据").foregroundColor(.secondary).font(.footnote)
                        } else {
                            let maxV = keys.map { att[$0] ?? 0 }.max() ?? 1
                            ForEach(keys, id: \.self) { k in
                                let v = att[k] ?? 0
                                HStack(spacing: 8) {
                                    Text(attitudeLabel[k] ?? k)
                                        .frame(width: 46, alignment: .leading)
                                        .font(.system(size: 12))
                                    GeometryReader { geo in
                                        HStack(spacing: 0) {
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(Color.accentColor)
                                                .frame(width: max(4, geo.size.width * CGFloat(v) / CGFloat(maxV)))
                                            Spacer(minLength: 0)
                                        }
                                    }
                                    .frame(height: 14)
                                    Text("\(v) 份（\(stats.store.total > 0 ? v * 100 / stats.store.total : 0)%）")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .frame(width: 88, alignment: .trailing)
                                }
                            }
                        }
                    }

                    card("答题人设分布") {
                        let prof = stats.store.profile
                        if prof.isEmpty {
                            Text("暂无数据").foregroundColor(.secondary).font(.footnote)
                        } else {
                            Text(prof.sorted { $0.value > $1.value }
                                .map { "\($0.key)：\($0.value) 份" }
                                .joined(separator: "　"))
                                .font(.footnote)
                        }
                    }

                    card("每一份的用时（最近 50 份）") {
                        let rows = Array(stats.store.recent.suffix(50))
                        if rows.isEmpty {
                            Text("暂无数据").foregroundColor(.secondary).font(.footnote)
                        } else {
                            let base = max(0, stats.store.total - rows.count)
                            ForEach(rows.indices, id: \.self) { idx in
                                let r = rows[idx]
                                HStack(spacing: 6) {
                                    Text("\(base + idx + 1)")
                                        .frame(width: 28, alignment: .trailing)
                                        .foregroundColor(.secondary)
                                    Text(r["ts"] as? String ?? "")
                                        .frame(width: 88, alignment: .leading)
                                    Text("\(r["elapsed"] as? Double ?? 0, specifier: "%.1f")s")
                                        .frame(width: 48, alignment: .trailing)
                                    Text(r["profile"] as? String ?? "")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .lineLimit(1)
                                    Text((r["ok"] as? Bool ?? false) ? "成功" : "失败")
                                        .foregroundColor((r["ok"] as? Bool ?? false) ? .green : .red)
                                }
                                .font(.system(size: 11, design: .monospaced))
                            }
                        }
                    }
                }
                .padding(14)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("累计统计")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("清零") {
                        stats.store.reset()
                        stats.refresh()
                    }
                    .foregroundColor(.red)
                }
            }
        }
    }

    private func kpi(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10)).foregroundColor(.secondary)
            Text(value).font(.system(size: 14, weight: .bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func card<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11)).foregroundColor(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
