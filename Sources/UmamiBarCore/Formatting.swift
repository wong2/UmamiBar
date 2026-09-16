import Foundation

public func compactNumber(_ value: Double) -> String {
    let abs = Swift.abs(value)
    if abs >= 1_000_000 {
        return String(format: "%.1fM", value / 1_000_000).replacingOccurrences(of: ".0M", with: "M")
    }
    if abs >= 1_000 {
        return String(format: "%.1fK", value / 1_000).replacingOccurrences(of: ".0K", with: "K")
    }
    if value.truncatingRemainder(dividingBy: 1) == 0 {
        return String(format: "%.0f", value)
    }
    return String(format: "%.1f", value)
}

public func percent(_ value: Double) -> String {
    String(format: "%.0f%%", value * 100)
}

public func duration(seconds: Double) -> String {
    let total = Int(seconds)
    let m = total / 60
    let s = total % 60
    if m >= 60 {
        let h = m / 60
        return String(format: "%dh %dm", h, m % 60)
    }
    return String(format: "%d:%02d", m, s)
}

public func relativeTime(_ date: Date) -> String {
    let interval = Date().timeIntervalSince(date)
    if interval < 5 { return "just now" }
    if interval < 60 { return String(format: "%.0fs ago", interval) }
    if interval < 3600 { return String(format: "%.0fm ago", interval / 60) }
    if interval < 86400 { return String(format: "%.0fh ago", interval / 3600) }
    return String(format: "%.0fd ago", interval / 86400)
}
