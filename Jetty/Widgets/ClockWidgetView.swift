import SwiftUI

/// The date/time dock tile (improvement #3). Renders the time in the chosen
/// `ClockFaceStyle` — plain text, a seven-segment LCD, or one of the analog
/// dials (`AnalogClockFace`) — ticking via a `TimelineView` so there are no
/// manual timers. Watch faces honor the Face-size zoom: a zoomed face pins to
/// the dock's edge and grows inward past the glass strip, like a permanently
/// magnified tile. String building lives in the pure `ClockFormatter`. See
/// PLAN.md §8.1.
struct ClockWidgetView: View {
    @ObservedObject var preferences: Preferences
    var height: CGFloat
    /// The dock edge this tile sits on — a zoomed face pins to it.
    var edge: DockEdge = .bottom
    /// The overflow-scroll dock suspends the zoom (its viewport clips).
    var allowsZoom: Bool = true

    var body: some View {
        let face = preferences.clockFace
        // Tick per second only when something visibly moves per second: seconds
        // digits, or an analog second hand — `AnalogClockFace` gates its second
        // hand on `clockShowSeconds`, and Color Time has no hands at all, so a
        // 1 Hz repaint there is pure waste (FAB-P1). Otherwise tick per minute.
        // Both cadences anchor at the minute boundary — a second boundary too —
        // so the shown minute never lags (M29) and per-second ticks land on
        // real second boundaries instead of an arbitrary phase (FAB-P2).
        let ticksEverySecond = preferences.clockShowSeconds && face.showsSecondsOption
        let schedule: PeriodicTimelineSchedule = .periodic(
            from: ClockFormatter.minuteStart(),
            by: ticksEverySecond ? 1 : 60)
        TimelineView(schedule) { context in
            switch face {
            case .digital:
                digital(date: context.date)
            case .lcd:
                // The LCD's box tracks the (zoom-widened) tile width; its case
                // sizes itself inside, so it grows with the face but never
                // outgrows the tile.
                faceBox(LCDClockFace(date: context.date,
                                     use24Hour: preferences.clockUse24Hour,
                                     showSeconds: preferences.clockShowSeconds),
                        width: height * DockLayout.clockTileWidthFactor(zoom: zoom),
                        faceHeight: height * zoom)
            default:
                faceBox(AnalogClockFace(date: context.date,
                                        style: face,
                                        showSeconds: preferences.clockShowSeconds,
                                        tint: preferences.tintColor),
                        width: height * 0.92 * zoom, faceHeight: height * 0.92 * zoom)
            }
        }
    }

    /// The effective face zoom: the Widgets ▸ Clock slider, for watch faces on
    /// horizontal docks. Vertical docks stay at 1× — there the face would grow
    /// *along* the dock and overlap the neighboring tiles.
    private var zoom: CGFloat {
        guard allowsZoom, edge.isHorizontal else { return 1 }
        return CGFloat(preferences.effectiveClockZoom)
    }

    /// Frames a watch face and, when zoomed, pins it to the dock's edge side so
    /// the extra size grows inward over the glass strip instead of spilling
    /// off-screen. **Keep the geometry in sync with
    /// `DockLayout.clockZoomHeadroom`** (edge padding = 0.04 × height, face box
    /// ≤ height × zoom across). Unzoomed faces keep the old centered layout.
    @ViewBuilder
    private func faceBox<Face: View>(_ face: Face, width: CGFloat, faceHeight: CGFloat) -> some View {
        if zoom > 1.001 {
            face
                .frame(width: width, height: faceHeight)
                .padding(edgeInsets)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edgeAlignment)
                .help("Open Calendar")
        } else {
            face
                .frame(width: width, height: faceHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .help("Open Calendar")
        }
    }

    /// Padding on the edge-facing side only, so the zoomed face keeps the same
    /// small gap to the screen edge the unzoomed (centered) face has.
    private var edgeInsets: EdgeInsets {
        let pad = height * 0.04
        switch edge {
        case .bottom: return EdgeInsets(top: 0, leading: 0, bottom: pad, trailing: 0)
        case .top:    return EdgeInsets(top: pad, leading: 0, bottom: 0, trailing: 0)
        case .left:   return EdgeInsets(top: 0, leading: pad, bottom: 0, trailing: 0)
        case .right:  return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: pad)
        }
    }

    private var edgeAlignment: Alignment {
        switch edge {
        case .bottom: return .bottom
        case .top: return .top
        case .left: return .leading
        case .right: return .trailing
        }
    }

    private func digital(date: Date) -> some View {
        let lines = ClockFormatter.lines(
            for: date,
            use24Hour: preferences.clockUse24Hour,
            showSeconds: preferences.clockShowSeconds,
            showDate: preferences.clockShowDate,
            showWeekday: preferences.clockShowWeekday)

        return VStack(spacing: 1) {
            Text(lines.primary)
                .font(.system(size: max(11, height * 0.32), weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)   // "10:00:00 PM" / small tiles must not wrap or clip (F-L7)
            if let secondary = lines.secondary {
                Text(secondary)
                    .font(.system(size: max(8, height * 0.2), weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .padding(.horizontal, 8)
        .frame(minWidth: height * 1.4)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .help("Open Calendar")
    }
}
