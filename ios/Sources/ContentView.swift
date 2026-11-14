import SwiftUI
import UIKit
import WebKit

@main
struct WjxApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct WebViewBox: UIViewRepresentable {
    let web: WKWebView
    func makeUIView(context: Context) -> WKWebView { web }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

@MainActor
struct ContentView: View {
    @StateObject private var filler = Filler()

    @State private var url = "https://v.wjx.cn/vm/O4hTZ85.aspx"
    @State private var countText = "10"
    @State private var durLow = "180"
    @State private var durHigh = "300"
    @State private var gapLow = "60"
    @State private var gapHigh = "180"
    @State private var attitude = "positive"
    @State private var persona = "auto"
    @State private var otherProb = "0"
    @State private var showWeb = false

    @State private var force: [String: String] = ["7": "1"]
    @State private var exclude: [String: [String]] = [:]
    @State private var otherTexts: [String: String] = [:]
    @State private var showForce = false
    @State private var showStats = false
    @StateObject private var statsWrapper = StatsStoreWrapper(StatsStore(url: ""))

    private let personas = ["auto", "青年学生", "青年在职", "中年在职", "自由职业"]
    private let attitudes = ["positive", "neutral", "negative", "mixed"]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 12) {
                    configCard
                    actionCard
                    statusCard
                    if showWeb {
                        WebViewBox(web: filler.web)
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.25)))
                    }
                    logCard
                }
                .padding(14)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("问卷助手")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                to: nil, from: nil, for: nil)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("收起键盘") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                        to: nil, from: nil, for: nil)
                    }
                    .font(.system(size: 12))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("统计详情") {
                            statsWrapper.store = filler.stats
                            showStats = true
                        }
                        Button("特定选项") { showForce = true }
                        Button(showWeb ? "隐藏网页" : "显示网页") { showWeb.toggle() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showForce) {
                ForceSheet(questions: filler.questions,
                           force: $force, exclude: $exclude, otherTexts: $otherTexts)
            }
            .sheet(isPresented: $showStats) {
                StatsSheet(stats: statsWrapper)
            }
        }
        .navigationViewStyle(.stack)
    }

    private var configCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("问卷链接").font(.system(size: 11)).foregroundColor(.secondary)
            TextField("https://v.wjx.cn/vm/xxxx.aspx", text: $url)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .keyboardType(.URL)

            HStack(spacing: 8) {
                labeled("份数", $countText)
                labeled("选其他概率", $otherProb)
            }
            HStack(spacing: 8) {
                labeled("单份用时 起", $durLow)
                labeled("止", $durHigh)
            }
            HStack(spacing: 8) {
                labeled("份间间隔 起", $gapLow)
                labeled("止", $gapHigh)
            }
            Picker("答题人设", selection: $persona) {
                ForEach(personas, id: \.self) { Text($0) }
            }
            .pickerStyle(.menu)
            Picker("答题倾向", selection: $attitude) {
                ForEach(attitudes, id: \.self) { Text($0) }
            }
            .pickerStyle(.segmented)
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func labeled(_ title: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10)).foregroundColor(.secondary)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.decimalPad)
        }
    }

    private var actionCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    Task { await filler.parseOnly(urlText: url) }
                } label: {
                    Text("解析问卷").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(filler.state != "idle")

                Button {
                    if !showWeb { showWeb = true }
                    var cfg = RunConfig()
                    cfg.url = url.trimmingCharacters(in: .whitespacesAndNewlines)
                    cfg.count = max(1, Int(countText) ?? 1)
                    cfg.durationLow = Double(durLow) ?? 180
                    cfg.durationHigh = Double(durHigh) ?? 300
                    cfg.intervalLow = Double(gapLow) ?? 60
                    cfg.intervalHigh = Double(gapHigh) ?? 180
                    cfg.attitude = attitude
                    cfg.persona = persona
                    cfg.otherProbability = Double(otherProb) ?? 0
                    cfg.forceAnswers = force
                    cfg.excludeAnswers = exclude
                    cfg.otherTexts = otherTexts
                    filler.start(config: cfg)
                } label: {
                    Text("开始").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(filler.state != "idle")

                Button {
                    filler.togglePause()
                } label: {
                    Text(filler.state == "paused" ? "继续" : "暂停").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(filler.state == "idle")

                Button(role: .destructive) {
                    filler.reset()
                } label: {
                    Text("重置").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(filler.state == "idle")
            }

            HStack(spacing: 8) {
                Button {
                    statsWrapper.store = filler.stats
                    showStats = true
                } label: {
                    Text("统计详情").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    showForce = true
                } label: {
                    Text("特定选项").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(filler.questions.isEmpty)

                Button {
                    showWeb.toggle()
                } label: {
                    Text(showWeb ? "隐藏网页" : "显示网页").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(showWeb ? .blue : nil)
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(filler.done) / \(max(1, filler.total))")
                    .font(.title2).bold()
                Spacer()
                Text(stateText)
                    .font(.system(size: 11))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(Capsule())
            }
            ProgressView(value: filler.total > 0
                         ? Double(filler.done) / Double(filler.total) : 0)
            HStack {
                Text("成功 \(filler.ok)").foregroundColor(.green).font(.system(size: 12))
                Text("失败 \(filler.fail)").foregroundColor(.red).font(.system(size: 12))
                Spacer()
                Text("IP \(filler.ip)").font(.system(size: 10)).foregroundColor(.secondary)
                    .lineLimit(1)
            }

            if filler.stats.total > 0 {
                Text("累计：\(filler.stats.total) 份 | 总用时 \(filler.stats.durationText()) | "
                     + "平均 \(String(format: "%.1f", filler.stats.averageSeconds)) 秒/份 | "
                     + "倾向 \(filler.stats.attitudeText())")
                    .font(.system(size: 10))
                    .foregroundColor(.green)
            }

            if filler.questionCount > 0 {
                Text("题库 \(filler.questionCount) 题 / \(filler.pageCount) 页"
                     + (force.isEmpty ? "" : " · 固定 \(force.count) 题")
                     + (exclude.isEmpty ? "" : " · 排除 \(exclude.count) 题"))
                    .font(.system(size: 10)).foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var stateText: String {
        switch filler.state {
        case "running": return "运行中"
        case "paused": return "已暂停"
        default: return "未开始"
        }
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("运行日志").font(.system(size: 11)).foregroundColor(.secondary)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(filler.logs.indices, id: \.self) { i in
                            Text(filler.logs[i])
                                .font(.system(size: 10, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(i)
                        }
                    }
                }
                .frame(height: 180)
                .onChange(of: filler.logs.count) { count in
                    guard count > 0 else { return }
                    withAnimation { proxy.scrollTo(count - 1, anchor: .bottom) }
                }
            }
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
