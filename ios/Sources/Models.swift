import Foundation

// MARK: - 题库模型

struct Question: Decodable, Identifiable {
    let topic: Int
    let type: Int
    let pg: Int
    let required: Bool
    let title: String
    let min: Int
    let max: Int
    let options: [QOption]
    let rows: [QRow]
    let scale: [String]

    var id: Int { topic }
    var topicKey: String { String(topic) }

    enum CodingKeys: String, CodingKey {
        case topic, type, pg, required, title, min, max, options, rows, scale
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        topic = (try? c.decode(Int.self, forKey: .topic)) ?? 0
        type = (try? c.decode(Int.self, forKey: .type)) ?? 0
        pg = (try? c.decode(Int.self, forKey: .pg)) ?? 1
        required = (try? c.decode(Bool.self, forKey: .required)) ?? true
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        min = (try? c.decode(Int.self, forKey: .min)) ?? 0
        max = (try? c.decode(Int.self, forKey: .max)) ?? 0
        options = (try? c.decode([QOption].self, forKey: .options)) ?? []
        rows = (try? c.decode([QRow].self, forKey: .rows)) ?? []
        scale = (try? c.decode([String].self, forKey: .scale)) ?? []
    }
}

struct QOption: Decodable, Hashable, Identifiable {
    let value: String
    let text: String
    let isOther: Bool
    let otherInput: String

    var id: String { value }

    enum CodingKeys: String, CodingKey { case value, text, isOther, otherInput }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value = (try? c.decode(String.self, forKey: .value)) ?? ""
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        isOther = (try? c.decode(Bool.self, forKey: .isOther)) ?? false
        otherInput = (try? c.decode(String.self, forKey: .otherInput)) ?? ""
    }
}

struct QRow: Decodable {
    let fid: String
    let index: Int
    let text: String
    let dvals: [String]

    enum CodingKeys: String, CodingKey { case fid, index, text, dvals }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fid = (try? c.decode(String.self, forKey: .fid)) ?? ""
        index = (try? c.decode(Int.self, forKey: .index)) ?? 0
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        dvals = (try? c.decode([String].self, forKey: .dvals)) ?? ["1","2","3","4","5"]
    }
}

// MARK: - 运行配置

struct RunConfig {
    var url: String = "https://v.wjx.cn/vm/O4hTZ85.aspx"
    var count: Int = 10
    var durationLow: Double = 180
    var durationHigh: Double = 300
    var intervalLow: Double = 60
    var intervalHigh: Double = 180
    var attitude: String = "positive"
    var persona: String = "auto"
    var otherProbability: Double = 0.0
    var otherMaxPerForm: Int = 2
    var forceAnswers: [String: String] = ["7": "1"]
    var excludeAnswers: [String: [String]] = [:]
    var otherTexts: [String: String] = [:]

    var duration: ClosedRange<Double> { min(durationLow, durationHigh)...max(durationLow, durationHigh) }
    var interval: ClosedRange<Double> { min(intervalLow, intervalHigh)...max(intervalLow, intervalHigh) }
}
