import SwiftUI

/// The pixelated composition graph: junk stacked by category as 3×10 ticks
/// (Usage bar tick, §3.2) — blue, fuchsia, orange, violet by size rank,
/// one white head at the total, dust for empty. Once per launch it reveals
/// in 14 whole steps; Reduce Motion renders the finished frame.
private struct CapsulelessTick: View {
    let isFilled: Bool
    let isHead: Bool
    let band: Color
    var body: some View {
        if isFilled {
            Rectangle().fill(isHead ? Tok.text : band)
        } else {
            Rectangle()
                .fill(Tok.controlPressed)
                .frame(width: Pixel.snap(1), height: Pixel.snap(1))
        }
    }
}

struct CompositionGraph: View {
    let sorted: [JunkCategory]
    let total: Int64
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    private struct Segment {
        let rank: Int
        let name: String
        let size: Int64
    }

    private var segments: [Segment] {
        sorted.filter { $0.totalSize > 0 }
            .enumerated()
            .map { Segment(rank: $0.offset, name: $0.element.kind.rawValue, size: $0.element.totalSize) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(total > 0 ? "Composition" : "No junk")
                .font(AppType.caption)
                .foregroundStyle(Tok.text2)
            GeometryReader { proxy in
                let count = max(1, Int(proxy.size.width / 4))
                let reveal = reduceMotion ? 1.0 : (revealed ? 1.0 : 0.0)
                HStack(spacing: 1) {
                    ForEach(0..<count, id: \.self) { i in
                        tick(at: i, count: count, reveal: reveal)
                    }
                }
            }
            .frame(height: 20)
            .onAppear {
                revealed = true
            }
            .animation(.easeOut(duration: 0.6), value: revealed)
            if total > 0, !segments.isEmpty {
                legendSegments
            }
        }
    }

    private func tick(at i: Int, count: Int, reveal: Double) -> some View {
        let position = Double(i) / Double(count)
        let filled = position < reveal
        let isHead = filled && i == Int(Double(count) * reveal) - 1
        let target = position * Double(total) / max(reveal, 0.001)
        var cumulative: Double = 0
        var band: Color = GraphPalette.color(forRank: 0)
        for segment in segments {
            cumulative += Double(segment.size)
            if target < cumulative {
                band = GraphPalette.color(forRank: segment.rank)
                break
            }
        }
        return ZStack(alignment: .center) {
            CapsulelessTick(isFilled: filled, isHead: isHead, band: band)
                .frame(width: Pixel.snap(3), height: Pixel.snap(10))
        }
        .frame(width: Pixel.snap(3), height: Pixel.snap(10))
    }

    private var legendSegments: some View {
        HStack(spacing: 16) {
            ForEach(Array(segments.prefix(4)), id: \.rank) { segment in
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(GraphPalette.color(forRank: segment.rank))
                        .frame(width: Pixel.snap(8), height: Pixel.snap(8))
                    Text(segment.name)
                        .font(AppType.caption)
                        .foregroundStyle(Tok.text2)
                        .lineLimit(1)
                    Text(share(segment.size))
                        .font(AppType.caption)
                        .monospacedDigit()
                        .foregroundStyle(Tok.text2)
                }
            }
            Spacer()
        }
    }

    private func share(_ size: Int64) -> String {
        let pct = Double(size) / Double(total) * 100
        return "\(Int(pct.rounded()))%"
    }
}
