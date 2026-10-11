import SwiftUI

/// The notch silhouette: concave flares where it meets the top edge, rounded bottom corners.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let tr = topRadius
        let br = min(bottomRadius, rect.height / 2, (rect.width - 2 * tr) / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + tr, y: rect.minY + tr), control: CGPoint(x: rect.minX + tr, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + tr, y: rect.maxY - br))
        path.addQuadCurve(to: CGPoint(x: rect.minX + tr + br, y: rect.maxY), control: CGPoint(x: rect.minX + tr, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - tr - br, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - tr, y: rect.maxY - br), control: CGPoint(x: rect.maxX - tr, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY + tr))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
