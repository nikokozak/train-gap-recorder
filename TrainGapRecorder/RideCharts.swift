import SwiftUI

/// The last minute of the ride as four charts on one time axis, one column per second, newest on
/// the right: service, the HTTPS round trip, UDP loss, and motion. A value sits in the second its
/// probe started in, so the charts line up even though a failed probe reports 4 s late.
struct RideCharts: View {
    var recentSeconds: [Int: RideSecond]
    var currentSecond: Int
    var isMotionAvailable: Bool

    /// Room on the left for the round-trip scale. Every chart keeps it, so the columns line up.
    fileprivate static let scaleWidth: CGFloat = 24
    /// Round trips are drawn on a log scale from 10 ms (a fast link; anything faster draws as the
    /// shortest bar) to the probe timeout, so that 50 ms stays low and a weak signal stands out.
    private static let roundTripScaleMinimumMS = 10.0
    private static let roundTripScaleMaximumMS = Recorder.probeTimeout * 1000
    /// A still phone jolts a few milli-g from sensor noise. The motion scale never goes below
    /// this, so that noise does not fill the chart.
    private static let motionScaleMinimumMilliG = 20.0

    var body: some View {
        let window = (currentSecond - Recorder.chartSeconds + 1...currentSecond).map { recentSeconds[$0] }
        VStack(alignment: .leading, spacing: 12) {
            chart("Service", value: serviceSummary(window), height: 14, columns: window.map(serviceColumn))
            chart(
                "Round trip", value: roundTripSummary(window), height: 40,
                columns: window.map(roundTripColumn),
                gridlines: [Gridline(fraction: Self.roundTripFraction(milliseconds: 1000), label: "1 s")]
            )
            chart("UDP loss", value: udpSummary(window), height: 20, columns: window.map(udpColumn))
            if isMotionAvailable {
                let scaleMilliG = max(Self.motionScaleMinimumMilliG, window.compactMap { $0?.joltMilliG }.max() ?? 0)
                chart("Motion", value: motionSummary(window), height: 40, columns: window.map { motionColumn($0, scaleMilliG: scaleMilliG) })
            } else {
                chartHeader("Motion", value: "No motion sensor")
            }
            HStack {
                Text("\(Recorder.chartSeconds) s ago")
                Spacer()
                Text("now")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.leading, Self.scaleWidth)
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }

    private func chart(_ title: String, value: String, height: CGFloat, columns: [Column?], gridlines: [Gridline] = []) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            chartHeader(title, value: value)
            ColumnChart(columns: columns, gridlines: gridlines)
                .frame(height: height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), last minute")
        .accessibilityValue(value)
    }

    private func chartHeader(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption.weight(.semibold))
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.leading, Self.scaleWidth)
    }

    // MARK: - Columns

    /// Green and full height with service; red and short without. Red and green alone are hard to
    /// tell apart for red-green colour blindness, so the height says it too.
    private func serviceColumn(_ second: RideSecond?) -> Column {
        switch second?.hasService {
        case true?: Column(fraction: 1, color: .green)
        case false?: Column(fraction: 0.4, color: .red)
        case nil: Column(fraction: 1, color: .secondary.opacity(0.15))  // The probe has not finished.
        }
    }

    private func roundTripColumn(_ second: RideSecond?) -> Column? {
        guard let roundTripMS = second?.roundTripMS else { return nil }
        return Column(fraction: Self.roundTripFraction(milliseconds: Double(roundTripMS)), color: .indigo)
    }

    private static func roundTripFraction(milliseconds: Double) -> Double {
        log10(max(roundTripScaleMinimumMS, milliseconds) / roundTripScaleMinimumMS) / log10(roundTripScaleMaximumMS / roundTripScaleMinimumMS)
    }

    /// The share of the second's UDP requests that got no reply.
    private func udpColumn(_ second: RideSecond?) -> Column? {
        guard let second, second.udpSentCount > 0 else { return nil }
        return Column(fraction: Double(second.udpLostCount) / Double(second.udpSentCount), color: .red)
    }

    private func motionColumn(_ second: RideSecond?, scaleMilliG: Double) -> Column? {
        guard let joltMilliG = second?.joltMilliG else { return nil }
        return Column(fraction: joltMilliG / scaleMilliG, color: .indigo)
    }

    // MARK: - Summaries (the text right of each chart title)

    /// "58 of 60 s"
    private func serviceSummary(_ window: [RideSecond?]) -> String {
        let known = window.compactMap { $0?.hasService }
        return "\(known.filter { $0 }.count) of \(known.count) s"
    }

    /// "38 ms now · slowest 2.1 s"
    private func roundTripSummary(_ window: [RideSecond?]) -> String {
        let latest = window.compactMap { $0 }.last { $0.hasService != nil }?.roundTripMS
        let slowest = window.compactMap { $0?.roundTripMS }.max()
        let now = latest.map { "\(Self.durationText(milliseconds: $0)) now" } ?? "no reply"
        return now + (slowest.map { " · slowest \(Self.durationText(milliseconds: $0))" } ?? "")
    }

    /// "3% lost"
    private func udpSummary(_ window: [RideSecond?]) -> String {
        let sentCount = window.reduce(0) { $0 + ($1?.udpSentCount ?? 0) }
        let lostCount = window.reduce(0) { $0 + ($1?.udpLostCount ?? 0) }
        guard sentCount > 0 else { return "—" }
        return "\(Int((Double(lostCount) / Double(sentCount) * 100).rounded()))% lost"
    }

    /// "23 mg now"
    private func motionSummary(_ window: [RideSecond?]) -> String {
        guard let latest = window.compactMap({ $0?.joltMilliG }).last else { return "—" }
        return "\(Int(latest.rounded())) mg now"
    }

    private static func durationText(milliseconds: Int) -> String {
        milliseconds < 1000 ? "\(milliseconds) ms" : String(format: "%.1f s", Double(milliseconds) / 1000)
    }
}

/// One second in a chart: a bar from the baseline, `fraction` of the chart's height.
private struct Column {
    var fraction: Double
    var color: Color
}

/// A horizontal hairline at `fraction` of the height, labelled in the scale area on the left.
private struct Gridline {
    var fraction: Double
    var label: String
}

/// Bars from a common baseline, one slot per column, 1 pt apart. A nil column draws nothing.
private struct ColumnChart: View {
    var columns: [Column?]
    var gridlines: [Gridline]

    @Environment(\.displayScale) private var displayScale
    private static let gap: CGFloat = 1
    private static let barCornerRadius: CGFloat = 1.5

    var body: some View {
        Canvas { context, size in
            let scaleWidth = RideCharts.scaleWidth
            let plotWidth = size.width - scaleWidth
            let hairline = 1 / displayScale
            let hairlineColor = GraphicsContext.Shading.color(.secondary.opacity(0.35))

            for gridline in gridlines {
                let y = size.height * (1 - gridline.fraction)
                context.fill(Path(CGRect(x: scaleWidth, y: y, width: plotWidth, height: hairline)), with: hairlineColor)
                context.draw(
                    Text(gridline.label).font(.caption2).foregroundStyle(.secondary),
                    at: CGPoint(x: scaleWidth - 4, y: y),
                    anchor: .trailing
                )
            }
            context.fill(Path(CGRect(x: scaleWidth, y: size.height - hairline, width: plotWidth, height: hairline)), with: hairlineColor)

            // Slots of (width + gap) / count: the last bar ends exactly at the right edge.
            let slotWidth = (plotWidth + Self.gap) / CGFloat(columns.count)
            for (index, column) in columns.enumerated() {
                guard let column, column.fraction > 0 else { continue }
                let height = max(hairline * 2, size.height * min(column.fraction, 1))
                let bar = CGRect(x: scaleWidth + CGFloat(index) * slotWidth, y: size.height - height, width: slotWidth - Self.gap, height: height)
                let radii = RectangleCornerRadii(topLeading: Self.barCornerRadius, bottomLeading: 0, bottomTrailing: 0, topTrailing: Self.barCornerRadius)
                context.fill(Path(roundedRect: bar, cornerRadii: radii), with: .color(column.color))
            }
        }
    }
}
