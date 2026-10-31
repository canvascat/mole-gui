import AppKit

enum AppIconFactory {
    static func image(side: CGFloat) -> NSImage {
        let size = NSSize(width: side, height: side)
        return NSImage(size: size, flipped: false) { rect in
            let teal = NSColor(calibratedRed: 0.12, green: 0.40, blue: 0.38, alpha: 1)
            teal.setFill()
            let outer = rect.insetBy(dx: rect.width * 0.02, dy: rect.height * 0.02)
            NSBezierPath(roundedRect: outer, xRadius: rect.width * 0.22, yRadius: rect.height * 0.22).fill()

            let window = rect.insetBy(dx: rect.width * 0.22, dy: rect.height * 0.24)
            NSColor.white.withAlphaComponent(0.96).setFill()
            NSBezierPath(roundedRect: window, xRadius: rect.width * 0.08, yRadius: rect.height * 0.08).fill()

            let dot = rect.width * 0.035
            let dotY = window.maxY - rect.height * 0.09
            for index in 0..<3 {
                let color: NSColor = index == 2 ? teal : NSColor(calibratedWhite: 0.78, alpha: 1)
                color.setFill()
                let origin = NSPoint(x: window.minX + rect.width * 0.07 + CGFloat(index) * rect.width * 0.055, y: dotY)
                NSBezierPath(ovalIn: NSRect(origin: origin, size: NSSize(width: dot, height: dot))).fill()
            }

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let font = NSFont.systemFont(ofSize: rect.width * 0.22, weight: .semibold)
            let title = "mo" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: teal,
                .paragraphStyle: paragraph,
            ]
            let textRect = NSRect(
                x: window.minX,
                y: window.minY + rect.height * 0.06,
                width: window.width,
                height: window.height * 0.55
            )
            title.draw(in: textRect, withAttributes: attributes)
            return true
        }
    }
}
