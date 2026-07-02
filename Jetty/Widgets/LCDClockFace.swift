import SwiftUI

/// A retro seven-segment LCD clock face drawn with `Canvas`: a pale khaki
/// "screen" with dark digits and the faint unlit ghost segments of a classic
/// 80s digital watch. Digit shapes come from the pure `SevenSegment` lookup;
/// the 12/24-hour fold from `ClockFormatter.displayHour`.
struct LCDClockFace: View {
    let date: Date
    var use24Hour: Bool
    var showSeconds: Bool

    private static let screen = Color(red: 0.69, green: 0.74, blue: 0.60)
    private static let ink = Color(red: 0.13, green: 0.16, blue: 0.12)

    var body: some View {
        Canvas { context, size in
            let screenH = min(size.height * 0.64, size.width * 0.42)
            let screenW = size.width - 2
            guard screenH > 8, screenW > 16 else { return }
            let screenRect = CGRect(x: (size.width - screenW) / 2, y: (size.height - screenH) / 2,
                                    width: screenW, height: screenH)
            let screenPath = Path(roundedRect: screenRect, cornerRadius: screenH * 0.18)
            context.fill(screenPath, with: .color(Self.screen))
            context.stroke(screenPath, with: .color(.black.opacity(0.35)), lineWidth: 1)

            let comps = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
            let (hour, meridiem) = ClockFormatter.displayHour(comps.hour ?? 0, use24Hour: use24Hour)
            let minute = comps.minute ?? 0
            let second = comps.second ?? 0

            // Natural metrics from the screen height, then scale everything down
            // uniformly if the row is wider than the screen allows.
            var digitH = screenH * 0.62
            var digitW = digitH * 0.55
            var gap = digitW * 0.28
            var thick = digitW * 0.22
            let secScale: CGFloat = 0.62
            let margin = screenH * 0.15

            func rowWidth() -> CGFloat {
                var w = 4 * digitW + thick + 4 * gap                       // HH : MM
                if showSeconds { w += gap + secScale * (2 * digitW + gap) }
                // AM/PM column — sized for the fixed "AM"/"PM" strings at the
                // digitH * 0.28 font below; revisit both together if either changes.
                if meridiem != nil { w += digitW * 0.9 + gap }
                return w
            }
            let usable = screenRect.width - 2 * margin
            if rowWidth() > usable {
                let scale = usable / rowWidth()
                digitH *= scale; digitW *= scale; gap *= scale; thick *= scale
            }

            let top = screenRect.midY - digitH / 2
            var x = screenRect.minX + margin + (usable - rowWidth()) / 2

            if let meridiem {
                // .foregroundColor, not .foregroundStyle: the Text-returning
                // foregroundStyle overload (needed for GraphicsContext.draw)
                // is macOS 14+, and the min target is 13.
                context.draw(
                    Text(meridiem)
                        .font(.system(size: digitH * 0.28, weight: .bold, design: .rounded))
                        .foregroundColor(Self.ink),
                    at: CGPoint(x: x + digitW * 0.45, y: top + digitH * 0.18), anchor: .center)
                x += digitW * 0.9 + gap
            }

            // A 12-hour clock leaves the hour-tens slot blank (ghost only), like
            // the real thing; 24-hour pads with a zero.
            let hourTens: Int? = (hour >= 10 || use24Hour) ? hour / 10 : nil
            drawDigit(context, hourTens, x: x, y: top, w: digitW, h: digitH, t: thick); x += digitW + gap
            drawDigit(context, hour % 10, x: x, y: top, w: digitW, h: digitH, t: thick); x += digitW + gap
            drawColon(context, x: x, y: top, h: digitH, t: thick); x += thick + gap
            drawDigit(context, minute / 10, x: x, y: top, w: digitW, h: digitH, t: thick); x += digitW + gap
            drawDigit(context, minute % 10, x: x, y: top, w: digitW, h: digitH, t: thick); x += digitW + gap

            if showSeconds {
                let sw = digitW * secScale, sh = digitH * secScale
                let st = thick * secScale, sg = gap * secScale
                let sTop = top + digitH - sh   // bottom-aligned, like a subdial
                drawDigit(context, second / 10, x: x, y: sTop, w: sw, h: sh, t: st); x += sw + sg
                drawDigit(context, second % 10, x: x, y: sTop, w: sw, h: sh, t: st)
            }
        }
        .contentShape(Rectangle())
    }

    /// One digit cell: every segment as a faint ghost, then the lit ones in ink.
    /// A `nil` digit draws the ghost only (the blank 12-hour tens slot).
    private func drawDigit(_ ctx: GraphicsContext, _ digit: Int?,
                           x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, t: CGFloat) {
        let lit = digit.flatMap(SevenSegment.segments(for:)) ?? []
        let midY = y + (h - t) / 2
        let vh = (h - t) / 2 - t
        let cells: [(SevenSegment.Segments, CGRect)] = [
            (.a, CGRect(x: x + t, y: y, width: w - 2 * t, height: t)),
            (.g, CGRect(x: x + t, y: midY, width: w - 2 * t, height: t)),
            (.d, CGRect(x: x + t, y: y + h - t, width: w - 2 * t, height: t)),
            (.f, CGRect(x: x, y: y + t, width: t, height: vh)),
            (.b, CGRect(x: x + w - t, y: y + t, width: t, height: vh)),
            (.e, CGRect(x: x, y: midY + t, width: t, height: vh)),
            (.c, CGRect(x: x + w - t, y: midY + t, width: t, height: vh)),
        ]
        for (segment, rect) in cells {
            let on = lit.contains(segment)
            ctx.fill(Path(roundedRect: rect, cornerRadius: t * 0.3),
                     with: .color(Self.ink.opacity(on ? 1.0 : 0.09)))
        }
    }

    private func drawColon(_ ctx: GraphicsContext, x: CGFloat, y: CGFloat, h: CGFloat, t: CGFloat) {
        for fraction in [0.32, 0.68] {
            let rect = CGRect(x: x, y: y + h * fraction - t / 2, width: t, height: t)
            ctx.fill(Path(roundedRect: rect, cornerRadius: t * 0.3), with: .color(Self.ink))
        }
    }
}
