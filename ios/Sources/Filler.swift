import Foundation
import SwiftUI
import UIKit
import WebKit

/// 主流程：加载问卷、解析题目、逐题点选、提交、记录统计
@MainActor
final class Filler: NSObject, ObservableObject {

    @Published var logs: [String] = []
    @Published var state = "idle"          // idle / running / paused
    @Published var done = 0
    @Published var total = 0
    @Published var ok = 0
    @Published var fail = 0
    @Published var ip = "-"
    @Published var questionCount = 0
    @Published var pageCount = 0
    @Published var stats = StatsStore(url: "")
    @Published private(set) var questions: [Question] = []

    let web: WKWebView
    private var cfg = RunConfig()
    private var book: SignatureBook?
    private var paused = false
    private var stopped = false
    private var running = false

    override init() {
        let conf = WKWebViewConfiguration()
        conf.allowsInlineMediaPlayback = true
        conf.defaultWebpagePreferences.allowsContentJavaScript = true
        web = WKWebView(frame: .zero, configuration: conf)
        super.init()
        web.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) "
            + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        UIApplication.shared.isIdleTimerDisabled = true
    }

    // MARK: 日志

    func log(_ text: String) {
        logs.append(text)
        if logs.count > 600 { logs.removeFirst(logs.count - 600) }
    }

    // MARK: 控制

    func start(config: RunConfig) {
        guard !running else { return }
        cfg = config
        running = true
        stopped = false
        paused = false
        state = "running"
        done = 0; ok = 0; fail = 0
        total = config.count
        logs.removeAll()
        Task { await runLoop() }
    }

    func togglePause() {
        guard running else { return }
        paused.toggle()
        state = paused ? "paused" : "running"
        log(paused ? "[暂停]" : "[继续]")
    }

    func reset() {
        stopped = true
        paused = false
        running = false
        state = "idle"
        done = 0; ok = 0; fail = 0
        log("[重置]")
    }

    private func checkpoint() async -> Bool {
        while paused && !stopped {
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return !stopped
    }

    // MARK: 主循环

    private func runLoop() async {
        defer {
            running = false
            state = "idle"
            UIApplication.shared.isIdleTimerDisabled = false
        }
        guard let url = URL(string: cfg.url) else {
            log("！链接无效"); return
        }

        book = SignatureBook(url: cfg.url)
        stats = StatsStore(url: cfg.url)
        if let b = book, b.count > 0 { log("[去重] 已有指纹 \(b.count) 条") }
        if stats.total > 0 {
            log("[统计] 累计 \(stats.total) 份，总用时 \(stats.durationText())")
        }

        await refreshIP()
        log("计划 \(cfg.count) 份｜单份 \(Int(cfg.durationLow))-\(Int(cfg.durationHigh)) 秒")

        await load(url)
        let n = await waitForFields()
        if n == 0 {
            log("！没解析到题目。点右上角「显示网页」看看是否被验证码拦住")
            return
        }
        questions = await fetchQuestions()
        questionCount = questions.count
        pageCount = Set(questions.map { $0.pg }).count
        guard !questions.isEmpty else {
            log("！页面有 \(n) 个题目元素，但解析失败"); return
        }
        log("[题库] \(questionCount) 题 / \(pageCount) 页")

        for i in 1...cfg.count {
            guard await checkpoint() else { break }
            let success = await fillOne(index: i, url: url)
            if success {
                ok += 1
            } else {
                fail += 1
            }
            done = i
            if i < cfg.count {
                let wait = Double.random(in: cfg.interval)
                log("等待 \(Int(wait)) 秒后继续…")
                await sleep(wait)
            }
        }
        log("结束：成功 \(ok)，失败 \(fail)")
    }

    // MARK: 单份

    private func fillOne(index: Int, url: URL) async -> Bool {
        let engine = AnswerEngine(cfg: cfg)
        var plan = engine.build(questions: questions)

        var tries = 0
        while let b = book, b.contains(plan.signature()), tries < 40 {
            plan = engine.build(questions: questions)
            tries += 1
        }
        book?.add(plan.signature())

        let t0 = Date()
        await load(url)

        // 逐页填
        let pages = Set(questions.map { $0.pg }).sorted()
        let perQ = max(1.0, Double.random(in: cfg.duration) / Double(max(1, questions.count)))

        for (pi, pg) in pages.enumerated() {
            let pageQs = questions.filter { $0.pg == pg }
            for q in pageQs {
                guard await checkpoint() else { return false }
                guard let val = plan.answers[q.topicKey] else { continue }

                if q.type == 3, let v = val as? String {
                    _ = await js(PageScripts.clickLabel(topic: q.topic, value: v))
                    if let txt = plan.otherTexts[v], !txt.isEmpty {
                        _ = await js(PageScripts.fillOther(topic: q.topic, value: v, text: txt))
                    }
                } else if q.type == 4, let vals = val as? [String] {
                    for v in vals {
                        _ = await js(PageScripts.clickLabel(topic: q.topic, value: v))
                    }
                    if let last = vals.last, let txt = plan.otherTexts[last], !txt.isEmpty {
                        _ = await js(PageScripts.fillOther(topic: q.topic, value: last, text: txt))
                    }
                } else if q.type == 6, let m = val as? [String: String] {
                    for (fid, dv) in m {
                        _ = await js(PageScripts.clickMatrix(fid: fid, dval: dv))
                    }
                }
                await sleep(Double.random(in: (perQ * 0.6)...(perQ * 1.3)))
            }

            if pi < pages.count - 1 {
                _ = await js(PageScripts.clearOverlay)
                _ = await js(PageScripts.nextPage)
                await sleep(0.9)
                _ = await js(PageScripts.clearOverlay)
            }
        }

        // 提交
        _ = await js(PageScripts.clearOverlay)
        _ = await js("() => { window.scrollTo(0, document.body.scrollHeight); }")
        await sleep(0.5)
        _ = await js(PageScripts.clearOverlay)
        _ = await js(PageScripts.submit)

        var code = "timeout"
        var joinid = ""
        for _ in 0..<25 {
            await sleep(1.0)
            if let r = await jsDict(PageScripts.readResult) {
                let jid = r["joinid"] as? String ?? ""
                let done = r["done"] as? Bool ?? false
                let c = r["code"] as? String ?? ""
                if !jid.isEmpty {
                    joinid = jid
                    code = c.isEmpty ? "10" : c
                    break
                }
                if done {
                    code = "10"
                    break
                }
            }
            if stopped { break }
        }

        let elapsed = Date().timeIntervalSince(t0)
        let okFlag = code.hasPrefix("10")
        log(String(format: "[%d/%d] %.1fs | %@/%@ | %@",
                   index, cfg.count, elapsed,
                   plan.profileName, plan.attitudeName,
                   okFlag ? "OK joinid=\(joinid)" : "FAIL code=\(code)"))

        stats.add(elapsed: elapsed, profileName: plan.profileName,
                  attitudeName: plan.attitudeName, ok: okFlag,
                  joinid: joinid, ip: ip)
        log("[统计] 累计 \(stats.total) 份，总用时 \(stats.durationText())，"
            + "平均 \(String(format: "%.1f", stats.averageSeconds)) 秒/份，倾向 \(stats.attitudeText())")
        book?.save()
        return okFlag
    }

    // MARK: WebView 操作

    private func load(_ url: URL) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            var finished = false
            let done: () -> Void = {
                if !finished { finished = true; cont.resume() }
            }
            web.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60))
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { done() }
        }
    }

    /// 等待页面出现题目（最多 25 秒）
    private func waitForFields(timeout: Double = 25) async -> Int {
        let steps = Int(timeout / 1.0)
        for _ in 0..<steps {
            if let s = await js(PageScripts.pageState) as? String,
               let d = s.data(using: .utf8),
               let st = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                let n = st["fields"] as? Int ?? 0
                if n > 0 { return n }
                if st["hasCaptcha"] as? Bool == true {
                    log("[页面] 检测到验证码，请在下方「显示网页」里手动完成")
                    return 0
                }
            }
            await sleep(1.0)
        }
        return 0
    }

    private func fetchQuestions() async -> [Question] {
        var all: [Int: Question] = [:]
        for _ in 0..<12 {
            if let json = await js(PageScripts.parse) as? String,
               let data = json.data(using: .utf8),
               let arr = try? JSONDecoder().decode([Question].self, from: data) {
                for q in arr { all[q.topic] = q }
            }
            _ = await js(PageScripts.clearOverlay)
            let moved = await jsBool(PageScripts.nextPage)
            if !moved { break }
            await sleep(1.0)
        }
        _ = await js(PageScripts.clearOverlay)
        return all.values.sorted { $0.topic < $1.topic }
    }

    /// 只解析不提交（界面「解析问卷」按钮）
    func parseOnly(urlText: String) async {
        cfg.url = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: cfg.url), !cfg.url.isEmpty else {
            log("！链接无效")
            return
        }
        log("[解析] 打开问卷…")
        await load(url)
        let n = await waitForFields()
        if n == 0 {
            let st = await js(PageScripts.pageState) as? String ?? "{}"
            log("[页面] 状态：\(st.prefix(200))")
            log("！没出现题目元素。点「显示网页」看看实际页面")
            return
        }
        questions = await fetchQuestions()
        questionCount = questions.count
        pageCount = Set(questions.map { $0.pg }).count
        if questions.isEmpty {
            log("！有 \(n) 个题目元素但解析失败")
        } else {
            let types = Dictionary(grouping: questions, by: { $0.type }).mapValues { $0.count }
            log("[解析] \(questionCount) 题 / \(pageCount) 页，题型 \(types)")
        }
        await refreshIP()
    }

    private func js(_ script: String) async -> Any? {
        await withCheckedContinuation { cont in
            web.evaluateJavaScript(script) { value, _ in
                cont.resume(returning: value)
            }
        }
    }

    private func jsBool(_ script: String) async -> Bool {
        (await js(script) as? Bool) ?? false
    }

    private func jsDict(_ script: String) async -> [String: Any]? {
        await js(script) as? [String: Any]
    }

    func refreshIP() async {
        let sources = [
            "https://api.ipify.org?format=json",
            "https://ipinfo.io/json",
            "https://api.ip.sb/jsonip",
        ]
        for src in sources {
            guard let url = URL(string: src) else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 8
            do {
                let (data, _) = try await URLSession.shared.data(for: req)
                if let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let a = d["ip"] as? String { ip = a; return }
                }
                if let s = String(data: data, encoding: .utf8) {
                    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.range(of: #"^\d{1,3}(\.\d{1,3}){3}$"#, options: .regularExpression) != nil {
                        ip = trimmed
                        return
                    }
                }
            } catch {
                continue
            }
        }
        ip = "检测失败"
    }

    private func sleep(_ seconds: Double) async {
        let ns = UInt64(max(0, seconds) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: ns)
    }
}

/// 去重：同一问卷的历史答案指纹
final class SignatureBook {
    private let key: String
    private var items: [String] = []
    private let limit = 20000

    init(url: String) {
        var hash: UInt64 = 1469598103934665603
        for b in url.lowercased().utf8 {
            hash ^= UInt64(b)
            hash = hash &* 1099511628211
        }
        key = "wjx.used." + String(hash, radix: 16)
        if let arr = UserDefaults.standard.array(forKey: key) as? [String] {
            items = Array(arr.suffix(limit))
        }
    }

    var count: Int { items.count }

    func contains(_ sig: String) -> Bool { items.contains(sig) }

    func add(_ sig: String) {
        items.append(sig)
        if items.count > limit { items.removeFirst(items.count - limit) }
    }

    func save() {
        UserDefaults.standard.set(items, forKey: key)
    }
}
