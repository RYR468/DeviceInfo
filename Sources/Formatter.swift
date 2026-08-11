import Foundation

/// 轻量格式化工具
enum Fmt {
    /// 字节数 → "x.x GB"（系统文件计数风格）
    static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .file)
    }

    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    /// 0.0~1.0 的占比 → "37%"
    static func percent(_ fraction: Double) -> String {
        let clamped = max(0, min(1, fraction))
        return String(format: "%.0f%%", clamped * 100)
    }
}
