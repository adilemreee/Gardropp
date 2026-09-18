import SwiftUI

/// The app's hanger mark — the same geometry as the app icon, so the launch
/// animation and the icon are visibly the same drawing.
struct HangerMark: Shape {
    /// Everything is laid out in a 1024×1024 design square and scaled to fit.
    private static let design: CGFloat = 1024

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / Self.design
        let dx = rect.midX - Self.design * scale / 2
        let dy = rect.midY - Self.design * scale / 2
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * scale, y: dy + y * scale)
        }

        var path = Path()
        // Hook: starts at the free end, curls over the top, meets the stem.
        path.addArc(
            center: point(434, 372),
            radius: 78 * scale,
            startAngle: .degrees(145),
            endAngle: .degrees(360),
            clockwise: false
        )
        path.addLine(to: point(512, 458))   // apex
        path.addLine(to: point(200, 700))   // left shoulder
        path.addLine(to: point(824, 700))   // bottom bar
        path.addLine(to: point(512, 458))   // right shoulder, back to the apex
        return path
    }

    /// Stroke weight for a given rendered size, matching the icon's proportions.
    static func lineWidth(for size: CGFloat) -> CGFloat {
        47 * size / design
    }

    /// Where the hook hangs — the natural pivot for a swing.
    static let pivot = UnitPoint(x: 434.0 / design, y: 294.0 / design)
}
