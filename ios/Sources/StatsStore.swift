import Foundation

/// 累计统计（UserDefaults 持久化，跨启动累计）
final class StatsStore {

    private let key: String
    private(set) var total = 0
    private(set) var okCount = 0
    private(set) var failCount = 0
    private(set) var totalSeconds: Double = 0
    private(set) var attitude: [String: Int] = [:]
    private(set) var profile: [String: Int] = [:]
    private(set) var recent: [[String: Any]] = []

    private let recentLimit = 300

    init(url: String) {
        key = "wjx.stats." + StatsStore.stableKey(url)
        load()
    }

    private static func stableKey(_ text: String) -> String {
        var hash: UInt64 = 1469598103934665603
        for byte in text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return String(hash, radix: 16)
    }

    private func load() {
        guard let d = UserDefaults.standard.dictionary(forKey: key) else { return }
        total = d["total"] as? Int ?? 0
        okCount = d["ok"] as? Int ?? 0
        failCount = d["fail"] as? Int ?? 0
        totalSeconds = d["seconds"] as? Double ?? 0
        attitude = d["attitude"] as? [String: Int] ?? [:]
        profile = d["profile"] as? [String: Int] ?? [:]
        recent = d["recent"] as? [[String: Any]] ?? []
    }

    func save() {
        let d: [String: Any] = [
            "total": total, "ok": okCount, "fail": failCount,
            "seconds": totalSeconds, "attitude": attitude,
            "profile": profile, "recent": recent,
        ]
        UserDefaults.standard.set(d, forKey: key)
    }

    func add(elapsed: Double, profileName: String, attitudeName: String,
             ok: Bool, joinid: String, ip: String) {
        total += 1
        if ok { okCount += 1 } else { failCount += 1 }
        totalSeconds += elapsed
        attitude[attitudeName, default: 0] += 1
        profile[profileName, default: 0] += 1

        let fmt = DateFormatter()
        fmt.dateFormat = "MM-dd HH:mm:ss"
        recent.append([
            "ts": fmt.string(from: Date()),
            "elapsed": (elapsed * 10).rounded() / 10,
            "profile": profileName,
            "attitude": attitudeName,
            "ok": ok,
            "joinid": joinid,
            "ip": ip,
        ])
        if recent.count > recentLimit {
            recent.removeFirst(recent.count - recentLimit)
        }
        save()
    }

    var averageSeconds: Double { total > 0 ? totalSeconds / Double(total) : 0 }

    var successRate: Int {
        total > 0 ? Int((Double(okCount) * 100 / Double(total)).rounded()) : 0
    }

    func durationText() -> String {
        if totalSeconds < 60 { return String(format: "%.0f 秒", totalSeconds) }
        if totalSeconds < 3600 { return String(format: "%.1f 分钟", totalSeconds / 60) }
        return String(format: "%.2f 小时", totalSeconds / 3600)
    }

    func attitudeText() -> String {
        let pos = attitude["positive"] ?? 0
        let neu = attitude["neutral"] ?? 0
        let neg = attitude["negative"] ?? 0
        var parts = ["正\(pos)", "中\(neu)", "负\(neg)"]
        if let mixed = attitude["mixed"], mixed > 0 { parts.append("随机\(mixed)") }
        return parts.joined(separator: " / ")
    }

    func reset() {
        total = 0; okCount = 0; failCount = 0
        totalSeconds = 0; attitude = [:]; profile = [:]; recent = []
        save()
    }
}

/// 让 SwiftUI 观察统计变化
final class StatsStoreWrapper: ObservableObject {
    @Published var store: StatsStore
    init(_ store: StatsStore) { self.store = store }
    func refresh() { objectWillChange.send() }
}
