import SwiftUI

/// A retro seven-segment LCD clock face drawn with `Canvas` — a whole little
/// sports watch, not just the readout: a dark resin case, a printed accent
/// ring around the pale khaki screen, dark digits with the faint unlit ghost
/// segments of a classic 80s digital watch, and tiny print accents below.
/// Digit shapes come from the pure `SevenSegment` lookup; the 12/24-hour fold
/// from `ClockFormatter.displayHour`.
struct LCDClockFace: View {
    let date: Date
    var use24Hour: Bool
    var showSeconds: Bool

    private static let screen = Color(red: 0.69, green: 0.74, blue: 0.60)
    private static let ink = Color(red: 0.13, green: 0.16, blue: 0.12)
    private static let print = Color(red: 0.30, green: 0.50, blue: 0.78)

    var body: some View {
        Canvas { context, size in
            // The resin case: a rounded square (wider than tall) centered in the tile.
            let caseH = size.height - 2
            let caseW = min(size.width - 2, caseH * 1.35)
            guard caseH > 16, caseW > 24 else { return }
            let caseRect = CGRect(x: (size.width - caseW) / 2, y: (size.height - caseH) / 2,
                                  width: caseW, height: caseH)
            let casePath = Path(roundedRect: caseRect, cornerRadius: caseH * 0.28)
            context.fill(casePath, with: .linearGradient(
                Gradient(colors: [Color(white: 0.30), Color(white: 0.12)]),
                startPoint: CGPoint(x: caseRect.midX, y: caseRect.minY),
                endPoint: CGPoint(x: caseRect.midX, y: caseRect.maxY)))
            context.stroke(casePath, with: .color(.black.opacity(0.6)), lineWidth: 1)

            // The screen, nudged up a touch to leave room for the print accents.
            let screenW = caseW * 0.80
            let screenH = caseH * 0.52
            let screenRect = CGRect(x: caseRect.midX - screenW / 2,
                                    y: caseRect.midY - screenH / 2 - caseH * 0.03,
                                    width: screenW, height: screenH)
            // The printed accent ring around the screen.
            let ringRect = screenRect.insetBy(dx: -caseH * 0.05, dy: -caseH * 0.05)
            context.stroke(Path(roundedRect: ringRect, cornerRadius: screenH * 0.22),
                           with: .color(Self.print), lineWidth: max(1, caseH * 0.03))
            let screenPath = Path(roundedRect: screenRect, cornerRadius: screenH * 0.16)
            context.fill(screenPath, with: .color(Self.screen))
            context.stroke(screenPath, with: .color(.black.opacity(0.35)), lineWidth: 1)

            // Tiny print accents under the screen — the spot the real ones put
            // "water resist" and the model name.
            let accentY = (screenRect.maxY + caseH * 0.05 + caseRect.maxY - caseH * 0.08) / 2
            let accentH = max(1, caseH * 0.045)
            context.fill(Path(roundedRect: CGRect(x: caseRect.midX - caseW * 0.16, y: accentY,
                                                  width: caseW * 0.13, height: accentH),
                              cornerRadius: accentH / 2),
                         with: .color(Color(red: 0.95, green: 0.75, blue: 0.15)))
            context.fill(Path(roundedRect: CGRect(x: caseRect.midX + caseW * 0.03, y: accentY,
                                                  width: caseW * 0.13, height: accentH),
                              cornerRadius: accentH / 2),
                         with: .color(Color(red: 0.85, green: 0.25, blue: 0.20)))

            drawReadout(context, screenRect: screenRect)
        }
        .contentShape(Rectangle())
    }

    /// The seven-segment readout inside `screenRect`.
    private func drawReadout(_ context: GraphicsContext, screenRect: CGRect) {
        let comps = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        let (hour, meridiem) = ClockFormatter.displayHour(comps.hour ?? 0, use24Hour: use24Hour)
        let minute = comps.minute ?? 0
        let second = comps.second ?? 0

        // Natural metrics from the screen height, then scale everything down
        // uniformly if the row is wider than the screen allows.
        var digitH = screenRect.height * 0.62
        var digitW = digitH * 0.55
        var gap = digitW * 0.28
        var thick = digitW * 0.22
        let secScale: CGFloat = 0.62
        let margin = screenRect.height * 0.15

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
