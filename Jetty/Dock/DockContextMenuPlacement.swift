import CoreGraphics

/// Pure screen-space placement for a native context menu. `topLeft` returns the point
/// expected by `NSMenu.popUp(positioning:at:in:)` when no item is positioned.
enum DockContextMenuPlacement {

    static func topLeft(menuSize: CGSize, sourcePoint: CGPoint, dockFrame: CGRect,
                        visibleFrame: CGRect, edge: DockEdge, gap: CGFloat = 6,
                        margin: CGFloat = 4) -> CGPoint {
        var point: CGPoint
        switch edge {
        case .bottom:
            point = CGPoint(x: sourcePoint.x - menuSize.width / 2,
                            y: dockFrame.maxY + gap + menuSize.height)
        case .top:
            point = CGPoint(x: sourcePoint.x - menuSize.width / 2,
                            y: dockFrame.minY - gap)
        case .left:
            point = CGPoint(x: dockFrame.maxX + gap,
                            y: sourcePoint.y + menuSize.height / 2)
        case .right:
            point = CGPoint(x: dockFrame.minX - gap - menuSize.width,
                            y: sourcePoint.y + menuSize.height / 2)
        }

        let minX = visibleFrame.minX + margin
        let maxX = max(minX, visibleFrame.maxX - margin - menuSize.width)
        let maxTop = visibleFrame.maxY - margin
        let minTop = min(maxTop, visibleFrame.minY + margin + menuSize.height)
        point.x = min(max(point.x, minX), maxX)
        point.y = min(max(point.y, minTop), maxTop)
        return point
    }

    /// Bottom-left frame origin for a popup-style *panel* (e.g. the Jetty Menu opened
    /// from its dock tile) placed adjacent to the dock like a menu — the same geometry
    /// as `topLeft`, converted to the origin `NSWindow.setFrameOrigin` expects.
    static func panelOrigin(panelSize: CGSize, sourcePoint: CGPoint, dockFrame: CGRect,
                            visibleFrame: CGRect, edge: DockEdge, gap: CGFloat = 8,
                            margin: CGFloat = 4) -> CGPoint {
        let top = topLeft(menuSize: panelSize, sourcePoint: sourcePoint,
                          dockFrame: dockFrame, visibleFrame: visibleFrame,
                          edge: edge, gap: gap, margin: margin)
        return CGPoint(x: top.x, y: top.y - panelSize.height)
    }

    static func dockStripFrame(panelFrame: CGRect, thickness: CGFloat,
                               edge: DockEdge) -> CGRect {
        let value = min(thickness, edge.isHorizontal ? panelFrame.height : panelFrame.width)
        switch edge {
        case .bottom:
            return CGRect(x: panelFrame.minX, y: panelFrame.minY,
                          width: panelFrame.width, height: value)
        case .top:
            return CGRect(x: panelFrame.minX, y: panelFrame.maxY - value,
                          width: panelFrame.width, height: value)
        case .left:
            return CGRect(x: panelFrame.minX, y: panelFrame.minY,
                          width: value, height: panelFrame.height)
        case .right:
            return CGRect(x: panelFrame.maxX - value, y: panelFrame.minY,
                          width: value, height: panelFrame.height)
        }
    }
}
