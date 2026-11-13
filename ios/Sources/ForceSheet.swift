import SwiftUI

/// 特定选项：为每道题指定必选 / 排除 / 「其他」填写内容
struct ForceSheet: View {
    let questions: [Question]
    @Binding var force: [String: String]
    @Binding var exclude: [String: [String]]
    @Binding var otherTexts: [String: String]
    @Environment(\.dismiss) private var dismiss

    @State private var selected: Int? = nil
    @State private var search = ""

    private let typeLabel: [Int: String] = [3: "单选", 4: "多选", 6: "矩阵"]

    private var filtered: [Question] {
        let usable = questions.filter { [3, 4, 6].contains($0.type) }
        guard !search.isEmpty else { return usable }
        return usable.filter { $0.title.contains(search) || String($0.topic) == search }
    }

    var body: some View {
        NavigationView {
            HStack(spacing: 0) {
                List(filtered) { q in
                    Button {
                        selected = q.topic
                    } label: {
                        HStack(spacing: 5) {
                            Text(mark(q))
                                .frame(width: 12)
                                .foregroundColor(.accentColor)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("第 \(q.topic) 题 · \(typeLabel[q.type] ?? "")")
                                    .font(.system(size: 11, weight: .semibold))
                                Text(q.title)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .listRowBackground(selected == q.topic
                                       ? Color.accentColor.opacity(0.12) : Color.clear)
                }
                .listStyle(.plain)
                .frame(width: 168)

                Divider()

                Group {
                    if let t = selected, let q = questions.first(where: { $0.topic == t }) {
                        editor(for: q)
                    } else {
                        VStack {
                            Spacer()
                            Text("从左侧选一道题").foregroundColor(.secondary).font(.footnote)
                            Spacer()
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("特定选项")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "搜索题目")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("清空") {
                        force = ["7": "1"]
                        exclude = [:]
                        otherTexts = [:]
                    }
                    .foregroundColor(.red)
                }
            }
        }
    }

    private func mark(_ q: Question) -> String {
        let key = q.topicKey
        let hasF = !(force[key] ?? "").isEmpty
        let hasE = !(exclude[key] ?? []).isEmpty
        if hasF && hasE { return "◐" }
        if hasF { return "●" }
        if hasE { return "⊘" }
        return "○"
    }

    @ViewBuilder
    private func editor(for q: Question) -> some View {
        let key = q.topicKey
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("第 \(q.topic) 题 · \(typeLabel[q.type] ?? "")")
                    .font(.system(size: 10)).foregroundColor(.secondary)
                Text(q.title).font(.system(size: 13))

                if q.type == 3 || q.type == 4 {
                    Text("勾「选」= 固定选它；勾「不选」= 排除它")
                        .font(.system(size: 10)).foregroundColor(.secondary)

                    VStack(spacing: 4) {
                        ForEach(q.options) { opt in
                            optionRow(q: q, opt: opt, key: key)
                        }
                    }

                    if q.options.contains(where: { $0.isOther }) {
                        otherEditor(key: key)
                    }
                } else {
                    Text("矩阵题：所有行统一打一个分，或保持随机")
                        .font(.system(size: 10)).foregroundColor(.secondary)
                    HStack(spacing: 6) {
                        ForEach(q.scale.isEmpty ? ["1","2","3","4","5"] : q.scale, id: \.self) { v in
                            Button(v) {
                                if force[key] == v {
                                    force[key] = nil
                                } else {
                                    force[key] = v
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(force[key] == v ? .accentColor : nil)
                        }
                    }
                }
            }
            .padding(14)
        }
    }

    private func optionRow(q: Question, opt: QOption, key: String) -> some View {
        let isChosen = force[key] == opt.value
        let isExcluded = (exclude[key] ?? []).contains(opt.value)

        return HStack(spacing: 6) {
            Button {
                toggleForce(q: q, opt: opt, key: key)
            } label: {
                Image(systemName: isChosen ? "checkmark.square.fill" : "square")
                    .foregroundColor(isChosen ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)

            Button {
                toggleExclude(q: q, opt: opt, key: key)
            } label: {
                Image(systemName: isExcluded ? "xmark.square.fill" : "square")
                    .foregroundColor(isExcluded ? .red : .secondary)
            }
            .buttonStyle(.plain)

            Text("\(opt.value). \(opt.text)")
                .font(.system(size: 11))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    private func otherEditor(key: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("选「其他」时写入的内容")
                .font(.system(size: 10)).foregroundColor(.secondary)
            TextField("留空 = 用内置文本池", text: Binding(
                get: { otherTexts[key] ?? "" },
                set: { otherTexts[key] = $0.isEmpty ? nil : $0 }
            ))
            .textFieldStyle(.roundedBorder)
        }
        .padding(.top, 8)
    }

    private func toggleForce(q: Question, opt: QOption, key: String) {
        if force[key] == opt.value {
            force[key] = nil
        } else {
            force[key] = opt.value
            if var list = exclude[key] {
                list.removeAll { $0 == opt.value }
                exclude[key] = list.isEmpty ? nil : list
            }
        }
    }

    private func toggleExclude(q: Question, opt: QOption, key: String) {
        var list = exclude[key] ?? []
        if let i = list.firstIndex(of: opt.value) {
            list.remove(at: i)
        } else {
            list.append(opt.value)
        }
        exclude[key] = list.isEmpty ? nil : list
        if force[key] == opt.value { force[key] = nil }
    }
}
