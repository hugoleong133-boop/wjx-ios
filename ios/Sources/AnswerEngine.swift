import Foundation

/// 答案生成：人设 + 倾向 + 互斥 + 强制/排除 + 「其他」文本
final class AnswerEngine {

    struct Profile {
        let age: [String]
        let edu: [String]
        let job: [[String]]
        let income: [String]
    }

    struct Attitude {
        let name: String
        let bias: Double
        let countMode: String
        let exclusiveP: Double
    }

    static let profiles: [String: Profile] = [
        "青年学生": Profile(age: ["1"], edu: ["2","3"], job: [["6"]], income: ["1","2"]),
        "青年在职": Profile(age: ["2"], edu: ["3","4"], job: [["6"],["6","2"]], income: ["3","4"]),
        "中年在职": Profile(age: ["3"], edu: ["3","4"], job: [["2"],["2","6"]], income: ["4","5"]),
        "自由职业": Profile(age: ["2","3"], edu: ["2","3"], job: [["6"],["3"]], income: ["2","3"]),
    ]

    static let attitudes: [String: Attitude] = [
        "positive": Attitude(name: "positive", bias: 1.0, countMode: "high", exclusiveP: 0.10),
        "neutral":  Attitude(name: "neutral",  bias: 0.0, countMode: "mid",  exclusiveP: 0.20),
        "negative": Attitude(name: "negative", bias: -1.0, countMode: "low", exclusiveP: 0.28),
    ]

    static let demographic: [(String, String)] = [
        ("性別", "gender"), ("性别", "gender"),
        ("年齡", "age"), ("年龄", "age"),
        ("教育", "edu"), ("學歷", "edu"), ("学历", "edu"),
        ("職業", "job"), ("职业", "job"),
        ("收入", "income"), ("月入", "income"),
    ]

    /// 互斥语义标签
    static let exclusivePairs: [(String, String)] = [
        ("全职", "兼职"), ("全职", "学生"), ("全职", "退休"), ("全职", "失业"),
        ("兼职", "退休"), ("兼职", "失业"), ("学生", "退休"), ("学生", "失业"),
        ("同意", "不同意"), ("从不", "经常"),
    ]

    static let tagKeywords: [String: [String]] = [
        "全职": ["全職", "全职"],
        "兼职": ["兼職", "兼职", "臨時", "临时"],
        "学生": ["學生", "学生", "在學", "在读"],
        "退休": ["退休"],
        "失业": ["待業", "待业", "失業", "失业", "無業", "无业"],
        "自雇": ["自由職業", "自由职业", "自僱", "自雇", "創業", "创业"],
        "家务": ["家庭主婦", "家庭主妇", "家務", "家务"],
        "同意": ["非常同意", "同意", "贊成", "赞成"],
        "不同意": ["不同意", "非常不同意", "反對", "反对"],
        "从不": ["從不", "从不", "未曾"],
        "经常": ["經常", "经常", "總是", "总是"],
    ]

    /// 「其他」文本池（按题号）
    static let otherTexts: [Int: [String]] = [
        5: ["在職培訓導師", "社團行政助理", "項目協調員"],
        6: ["文化活動策劃", "長者服務助理", "青年項目統籌"],
        12: ["希望增加就業配對", "期望提供技能培訓", "建議加強灣區資訊"],
        14: ["粵港澳大灣區", "橫琴深合區", "澳門本地"],
        19: ["希望有更多實習機會", "期望增加創業支援", "建議提供進修補貼"],
        20: ["關注跨境醫療", "關注養老保障", "關注青年置業"],
    ]

    let cfg: RunConfig
    var personaName: String
    var attitude: Attitude
    private var profile: Profile
    private var rng = SystemRandomNumberGenerator()

    init(cfg: RunConfig, persona: String? = nil, attitudeName: String? = nil) {
        self.cfg = cfg
        let p = persona ?? cfg.persona
        if p == "auto" {
            personaName = AnswerEngine.profiles.keys.sorted().randomElement() ?? "青年在职"
        } else {
            personaName = AnswerEngine.profiles[p] != nil ? p : "青年在职"
        }
        profile = AnswerEngine.profiles[personaName]!

        let a = attitudeName ?? cfg.attitude
        if a == "mixed" {
            attitude = AnswerEngine.attitudes.randomElement()!.value
        } else {
            attitude = AnswerEngine.attitudes[a] ?? AnswerEngine.attitudes["positive"]!
        }
    }

    // MARK: 工具

    private func rand(_ range: ClosedRange<Double>) -> Double {
        Double.random(in: range)
    }

    private func weightedIndex(_ weights: [Double]) -> Int {
        let total = weights.reduce(0, +)
        guard total > 0 else { return Int.random(in: 0..<max(1, weights.count)) }
        var r = Double.random(in: 0...total)
        for (i, w) in weights.enumerated() {
            r -= w
            if r <= 0 { return i }
        }
        return weights.count - 1
    }

    private func positionWeights(_ n: Int, bias: Double, sharp: Double = 2.4) -> [Double] {
        guard n > 1 else { return [1.0] }
        var ws: [Double] = []
        for i in 0..<n {
            let pos = Double(i) / Double(n - 1)
            let center = 0.5 - 0.25 * bias
            let d = abs(pos - center)
            ws.append(max(0.02, 1.0 / (1.0 + pow(d * sharp, 2))))
        }
        return ws
    }

    private func tags(_ text: String) -> Set<String> {
        var out = Set<String>()
        for (tag, kws) in AnswerEngine.tagKeywords {
            if kws.contains(where: { text.contains($0) }) { out.insert(tag) }
        }
        return out
    }

    /// 选项值 -> 互斥集合
    func conflictGraph(_ q: Question) -> [String: Set<String>] {
        var g: [String: Set<String>] = [:]
        var tagmap: [String: Set<String>] = [:]
        for o in q.options {
            let t = tags(o.text)
            if !t.isEmpty { tagmap[o.value] = t }
        }
        for (a, ta) in tagmap {
            for (b, tb) in tagmap where a != b {
                for (x, y) in AnswerEngine.exclusivePairs {
                    if (ta.contains(x) && tb.contains(y)) || (ta.contains(y) && tb.contains(x)) {
                        g[a, default: []].insert(b)
                    }
                }
            }
        }
        return g
    }

    private func excluded(_ q: Question) -> Set<String> {
        Set(cfg.excludeAnswers[q.topicKey] ?? [])
    }

    private func forced(_ q: Question) -> String? {
        cfg.forceAnswers[q.topicKey]
    }

    private func otherText(for q: Question) -> String? {
        if let custom = cfg.otherTexts[q.topicKey], !custom.trimmingCharacters(in: .whitespaces).isEmpty {
            return custom
        }
        if let pool = AnswerEngine.otherTexts[q.topic] {
            return pool.randomElement()
        }
        return "其他"
    }

    // MARK: 逐题作答

    func answerSingle(_ q: Question) -> String? {
        guard !q.options.isEmpty else { return nil }
        if let f = forced(q), q.options.contains(where: { $0.value == f }) { return f }
        let banned = excluded(q)
        let usable = q.options.filter { !banned.contains($0.value) }
        let base = usable.isEmpty ? q.options : usable
        let normal = base.filter { !$0.isOther }
        let pool = normal.isEmpty ? base : normal

        for (kw, key) in AnswerEngine.demographic where q.title.contains(kw) {
            let want: [String]
            switch key {
            case "age": want = profile.age
            case "edu": want = profile.edu
            case "income": want = profile.income
            case "job": want = profile.job.first ?? []
            default: want = []
            }
            if let v = want.first, pool.contains(where: { $0.value == v }) { return v }
            break
        }

        if pool.count == 2 {
            let pFirst = 0.5 + 0.06 * attitude.bias
            return Double.random(in: 0...1) < pFirst ? pool[0].value : pool[1].value
        }
        let ws = positionWeights(pool.count, bias: attitude.bias)
        return pool[weightedIndex(ws)].value
    }

    func answerMulti(_ q: Question) -> [String] {
        guard !q.options.isEmpty else { return [] }
        if let f = forced(q) {
            return [f].filter { v in q.options.contains(where: { $0.value == v }) }
        }
        let banned = excluded(q)
        let usable = q.options.filter { !banned.contains($0.value) }
        let base = usable.isEmpty ? q.options : usable
        let normal = base.filter { !$0.isOther }
        let pool = normal.isEmpty ? base : normal

        let nMin = max(1, q.min)
        var nMax = q.max > 0 ? q.max : min(4, pool.count)
        nMax = max(nMin, min(nMax, pool.count))

        var n: Int
        switch attitude.countMode {
        case "high": n = Double.random(in: 0...1) < 0.65 ? nMax : max(nMin, nMax - 1)
        case "low": n = nMin
        case "mid": n = Int.random(in: nMin...max(nMin, min(nMax, 3)))
        default: n = Int.random(in: nMin...nMax)
        }
        n = max(nMin, min(n, pool.count))

        let g = conflictGraph(q)
        var chosen: [String] = []
        for idx in pool.indices.shuffled() {
            if chosen.count >= n { break }
            let v = pool[idx].value
            if chosen.contains(where: { g[$0]?.contains(v) == true }) { continue }
            chosen.append(v)
        }
        return chosen.isEmpty ? [pool[0].value] : chosen
    }

    func answerMatrix(_ q: Question) -> [String: String] {
        var out: [String: String] = [:]
        guard !q.rows.isEmpty else { return out }
        let scale = q.scale.isEmpty ? ["1","2","3","4","5"] : q.scale
        let banned = excluded(q)
        let usable = scale.filter { !banned.contains($0) }
        let pool = usable.isEmpty ? scale : usable
        let f = forced(q)
        for row in q.rows {
            if let f = f, pool.contains(f) {
                out[row.fid] = f
                continue
            }
            let ws = positionWeights(pool.count, bias: attitude.bias, sharp: 1.8)
            out[row.fid] = pool[weightedIndex(ws)]
        }
        return out
    }

    /// 按概率加入「其他」
    func maybeOther(_ q: Question, picked: [String]) -> (values: [String], note: [String: String]) {
        guard cfg.otherProbability > 0, !picked.isEmpty else { return (picked, [:]) }
        guard let other = q.options.first(where: { $0.isOther }) else { return (picked, [:]) }
        if excluded(q).contains(other.value) { return (picked, [:]) }
        for (kw, _) in AnswerEngine.demographic where q.title.contains(kw) { return (picked, [:]) }
        guard Double.random(in: 0...1) <= cfg.otherProbability else { return (picked, [:]) }

        let text = otherText(for: q) ?? ""
        let note = other.otherInput.isEmpty ? [:] : [other.value: text]

        if q.type == 3 { return ([other.value], note) }

        let g = conflictGraph(q)
        let blocked = g[other.value] ?? []
        let remain = picked.filter { !blocked.contains($0) && $0 != other.value }
        let nMin = max(1, q.min)
        if remain.count < nMin { return ([other.value], note) }
        let nMax = q.max > 0 ? q.max : min(4, q.options.count)
        var final = Array(remain.prefix(max(0, nMax - 1)))
        final.append(other.value)
        return (final, note)
    }

    // MARK: 整份计划

    struct Plan {
        var answers: [String: Any]
        var otherTexts: [String: String]
        var profileName: String
        var attitudeName: String

        func signature() -> String {
            var norm: [String: String] = [:]
            for (k, v) in answers {
                if let arr = v as? [String] {
                    norm[k] = arr.sorted().joined(separator: "|")
                } else if let dict = v as? [String: String] {
                    norm[k] = dict.sorted { $0.key < $1.key }
                        .map { "\($0.key):\($0.value)" }.joined(separator: ",")
                } else {
                    norm[k] = String(describing: v)
                }
            }
            let blob = norm.sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }.joined(separator: ";")
            return blob
        }
    }

    func build(questions: [Question]) -> Plan {
        var answers: [String: Any] = [:]
        var otherTexts: [String: String] = [:]
        var otherUsed = 0

        for q in questions {
            if q.type == 3 {
                guard let v = answerSingle(q) else { continue }
                var values = [v]
                if otherUsed < cfg.otherMaxPerForm {
                    let (vals, note) = maybeOther(q, picked: [v])
                    if !note.isEmpty {
                        otherUsed += 1
                        otherTexts.merge(note) { _, new in new }
                        values = vals
                    }
                }
                answers[q.topicKey] = values.first ?? v
            } else if q.type == 4 {
                var picked = answerMulti(q)
                guard !picked.isEmpty else { continue }
                if otherUsed < cfg.otherMaxPerForm {
                    let (vals, note) = maybeOther(q, picked: picked)
                    if !note.isEmpty {
                        otherUsed += 1
                        otherTexts.merge(note) { _, new in new }
                        picked = vals
                    }
                }
                answers[q.topicKey] = picked
            } else if q.type == 6 {
                let m = answerMatrix(q)
                if !m.isEmpty { answers[q.topicKey] = m }
            }
        }
        return Plan(answers: answers, otherTexts: otherTexts,
                    profileName: personaName, attitudeName: attitude.name)
    }
}
