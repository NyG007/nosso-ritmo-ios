import Foundation

public struct WidgetEvent: Codable, Identifiable {
    public var id: String
    public var title: String
    public var date: Date
    public var url: URL
    public init(id: String, title: String, date: Date, url: URL) {
        self.id = id; self.title = title; self.date = date; self.url = url
    }
}
public struct WidgetGoal: Codable, Identifiable {
    public var id: String
    public var title: String
    public var value: Double
    public var target: Double
    public init(id: String, title: String, value: Double, target: Double) {
        self.id = id; self.title = title; self.value = value; self.target = target
    }
}
public struct WidgetSnapshot: Codable {
    public var generatedAt: Date
    public var weekEnd: Date
    public var theme: String
    public var events: [WidgetEvent]
    public var goals: [WidgetGoal]
    public init(generatedAt: Date, weekEnd: Date, theme: String, events: [WidgetEvent], goals: [WidgetGoal]) {
        self.generatedAt = generatedAt; self.weekEnd = weekEnd; self.theme = theme; self.events = events; self.goals = goals
    }
}
