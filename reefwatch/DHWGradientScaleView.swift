import SwiftUI

/// Horizontal notched gradient bar(s) that mirror NOAA's DHW bleaching-alert scale.
///
/// • DHW < 20: a single bar from 0 → 20, gradient pale-blue → near-black at Alert 5.
/// • DHW 20-40: a second bar stacks on top, gradient continuing from the prior bar's
///              right-edge color down to pure black at 40. White separation notches.
/// • DHW 40-50: a third bar stacks on top, solid black with white notches at 40/50/60.
/// • DHW > 50:  bars are replaced with a large red number + "Degree Heating Weeks"
///              caption.
///
/// The red pointer triangle sits on the bar whose range contains `currentDHW`.
struct DHWGradientScaleView: View {
    let currentDHW: Double

    var body: some View {
        if currentDHW > 50 {
            HugeNumberView(dhw: currentDHW)
        } else {
            VStack(spacing: 4) {
                if currentDHW >= 40 {
                    ScaleBar(range: 40...60,
                             pointer: currentDHW <= 50 ? currentDHW : nil,
                             style: .solidBlack)
                }
                if currentDHW >= 20 {
                    ScaleBar(range: 20...40,
                             pointer: (currentDHW >= 20 && currentDHW < 40) ? currentDHW : nil,
                             style: .gradientToBlack)
                }
                ScaleBar(range: 0...20,
                         pointer: currentDHW < 20 ? currentDHW : nil,
                         style: .standardGradient)
            }
        }
    }
}

// MARK: - Single bar

private struct ScaleBar: View {
    enum Style { case standardGradient, gradientToBlack, solidBlack }

    let range: ClosedRange<Double>
    let pointer: Double?
    let style: Style

    var body: some View {
        GeometryReader { geo in
            let barHeight: CGFloat = 14
            let pointerSize: CGFloat = 10
            let width = geo.size.width
            let span  = range.upperBound - range.lowerBound

            VStack(spacing: 3) {
                pointerRow(width: width, span: span, pointerSize: pointerSize)
                barRow(barHeight: barHeight, width: width, span: span)
                labelsRow(width: width, span: span)
            }
        }
        .frame(height: 44)
    }

    private func pointerRow(width: CGFloat, span: Double, pointerSize: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Color.clear.frame(height: pointerSize)
            if let p = pointer {
                let clamped = min(max(p, range.lowerBound), range.upperBound)
                let x = CGFloat((clamped - range.lowerBound) / span) * width
                Triangle()
                    .fill(Color.red)
                    .frame(width: pointerSize, height: pointerSize)
                    .offset(x: x - pointerSize / 2)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
            }
        }
    }

    @ViewBuilder
    private func barRow(barHeight: CGFloat, width: CGFloat, span: Double) -> some View {
        ZStack(alignment: .leading) {
            barFill
                .frame(height: barHeight)
                .clipShape(RoundedRectangle(cornerRadius: 3))

            ForEach(notchValues, id: \.self) { v in
                Rectangle()
                    .fill(notchColor)
                    .frame(width: 1.5, height: barHeight + 4)
                    .offset(x: CGFloat((v - range.lowerBound) / span) * width - 0.75, y: 0)
            }
        }
        .frame(height: barHeight + 4)
    }

    private func labelsRow(width: CGFloat, span: Double) -> some View {
        ZStack(alignment: .leading) {
            Color.clear.frame(height: 12)
            ForEach(notchValues, id: \.self) { v in
                Text("\(Int(v))")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .offset(x: CGFloat((v - range.lowerBound) / span) * width - 8)
            }
        }
    }

    private var notchValues: [Double] {
        // Six notches every 4 units on every bar, so all three rows have the
        // same visual density and label spacing as the standard 0-20 bar.
        switch style {
        case .standardGradient: return [0,  4,  8, 12, 16, 20]
        case .gradientToBlack:  return [20, 24, 28, 32, 36, 40]
        case .solidBlack:       return [40, 44, 48, 52, 56, 60]
        }
    }

    private var notchColor: Color {
        switch style {
        case .standardGradient: return Color.black.opacity(0.55)
        case .gradientToBlack, .solidBlack: return Color.white.opacity(0.95)
        }
    }

    @ViewBuilder
    private var barFill: some View {
        switch style {
        case .standardGradient:
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.80, green: 0.92, blue: 1.00), location: 0.0),    // pale blue (No Stress)
                    .init(color: Color(red: 1.00, green: 0.95, blue: 0.30), location: 0.0005), // yellow (Watch)
                    .init(color: Color(red: 1.00, green: 0.55, blue: 0.10), location: 0.20),   // orange (Warning)
                    .init(color: Color(red: 0.90, green: 0.10, blue: 0.10), location: 0.40),   // red (Alert 1)
                    .init(color: Color(red: 0.62, green: 0.05, blue: 0.05), location: 0.60),   // dark red (Alert 2)
                    .init(color: Color(red: 0.40, green: 0.02, blue: 0.10), location: 0.80),   // maroon (Alert 3)
                    .init(color: Color(red: 0.15, green: 0.00, blue: 0.05), location: 1.00)    // near-black (Alert 4)
                ],
                startPoint: .leading,
                endPoint:   .trailing
            )
        case .gradientToBlack:
            // Picks up where the standard bar ended (~near-black at Alert 4/5)
            // and continues down to pure black at the right edge.
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.15, green: 0.00, blue: 0.05), location: 0.0),
                    .init(color: Color.black,                                location: 1.0)
                ],
                startPoint: .leading,
                endPoint:   .trailing
            )
        case .solidBlack:
            Color.black
        }
    }
}

// MARK: - DHW > 50 display

private struct HugeNumberView: View {
    let dhw: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(format: "%.0f", dhw))
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(Color.red)
            Text("Degree Heating Weeks")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Helpers

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to:   CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
