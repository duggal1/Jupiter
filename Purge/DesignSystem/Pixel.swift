import SwiftUI
import AppKit
import Combine

/// Pixel canvas — DESIGN.md §3. Square cells, antialiased false, whole-pixel origin.
enum Pixel {
    static var scale: CGFloat {
        (NSScreen.main?.backingScaleFactor ?? 2)
    }

    static func snap(_ value: CGFloat) -> CGFloat {
        round(value * scale) / scale
    }

    static func unit(cell: CGFloat) -> CGFloat {
        max(1 / scale, round(cell * scale) / scale)
    }

    static func cellHash(_ i: Int, _ j: Int, seed: Int = 0) -> Double {
        var h = 0.0
        h = Double((i * 374761393 + j * 668265263 + seed * 1013904223) & 0x7fffffff)
        h = (h * 1103515245 + 12345) / Double(0x7fffffff)
        return h - floor(h)
    }
}

private struct PixelGrid: View {
    let cols: Int
    let rows: Int
    let cell: CGFloat
    let tone: (Int, Int) -> Color?

    var body: some View {
        let pitch = cell
        let totalWidth = Pixel.snap(pitch * CGFloat(cols))
        let totalHeight = Pixel.snap(pitch * CGFloat(rows))
        ZStack(alignment: .topLeading) {
            ForEach(0..<cols, id: \.self) { i in
                ForEach(0..<rows, id: \.self) { j in
                    if let color = tone(i, j) {
                        Rectangle()
                            .fill(color)
                            .frame(width: Pixel.snap(cell), height: Pixel.snap(cell))
                            .position(x: Pixel.snap(pitch * CGFloat(i) + cell / 2), y: Pixel.snap(pitch * CGFloat(j) + cell / 2))
                    }
                }
            }
        }
        .frame(width: totalWidth, height: totalHeight)
    }
}

/// Bitmap renderer for `#` marks (§3.5).
struct PixelBitmap: View {
    let rows: [String]
    let cell: CGFloat
    let color: Color

    var body: some View {
        PixelGrid(cols: rows.first?.count ?? 0, rows: rows.count, cell: cell) { i, j in
            let row = rows[j]
            let char = Array(row)[i]
            return char == "#" ? color : nil
        }
    }
}

/// The pixel stop — the signature (§3.3). 5×5 disc, value per cell
/// v = 0.80 − 0.22·t² + (hash − 0.5)·0.12, tone bands 0.42/0.49/0.55/0.61.
struct PixelStop: View {
    var cell: CGFloat = 1.5
    var seed: Int = 0

    var body: some View {
        let n = 5
        PixelGrid(cols: n, rows: n, cell: cell) { i, j in
            let cx = Double(n - 1) / 2
            let dx = Double(i) - cx
            let dy = Double(j) - cx
            let t = (dx * dx + dy * dy).squareRoot() / cx
            let speckle = (Pixel.cellHash(i, j, seed: seed) < 0.16 && t > 0 && t < 0.9) ? -0.17 : 0.0
            let v = 0.80 - 0.22 * t * t + (Pixel.cellHash(i, j, seed: seed + 7) - 0.5) * 0.12 + speckle
            let mid: Color = .dynamic(light: 0x93C5FD, dark: 0x1E3A8A)
            let pale: Color = .hex(0x2563EB)
            let even = (i + j) % 2 == 0
            if v < 0.42 { return nil }
            if v < 0.49 { return even ? mid : nil }
            if v < 0.55 { return mid }
            if v < 0.61 { return even ? pale : mid }
            return pale
        }
    }
}

/// 7×7 disc bitmap for dialog headers.
struct PixelDisc: View {
    var cell: CGFloat = 2

    var body: some View {
        PixelBitmap(rows: [
            "..###..",
            ".#####.",
            "#######",
            "#######",
            "#######",
            ".#####.",
            "..###..",
        ], cell: cell, color: Tok.accent)
    }
}

/// Empty-state stop: 11×11, cell 4 (3 in panes). Same banded dither as PixelStop.
struct PixelEmptyStop: View {
    var cell: CGFloat = 4
    var body: some View {
        let n = 11
        PixelGrid(cols: n, rows: n, cell: cell) { i, j in
            let cx = Double(n - 1) / 2
            let dx = Double(i) - cx
            let dy = Double(j) - cx
            let t = (dx * dx + dy * dy).squareRoot() / cx
            let speckle = (Pixel.cellHash(i, j, seed: 3) < 0.16 && t > 0 && t < 0.9) ? -0.17 : 0.0
            let v = 0.80 - 0.22 * t * t + (Pixel.cellHash(i, j, seed: 11) - 0.5) * 0.12 + speckle
            let mid: Color = .dynamic(light: 0x93C5FD, dark: 0x1E3A8A)
            let pale: Color = .hex(0x2563EB)
            let even = (i + j) % 2 == 0
            if v < 0.42 { return nil }
            if v < 0.49 { return even ? mid : nil }
            if v < 0.55 { return mid }
            if v < 0.61 { return even ? pale : mid }
            return pale
        }
    }
}

struct PixelCheck: View {
    var cell: CGFloat = 1
    var body: some View {
        PixelBitmap(rows: [
            "......#",
            ".....#.",
            "#...#..",
            ".#.#...",
            "..#....",
        ], cell: cell, color: Tok.accentText)
    }
}

struct PixelFailed: View {
    var cell: CGFloat = 1
    var body: some View {
        PixelBitmap(rows: [
            "#...#",
            ".#.#.",
            "..#..",
            ".#.#.",
            "#...#",
        ], cell: cell, color: Tok.statusBad)
    }
}

struct PixelExclamation: View {
    var cell: CGFloat = 1
    var color: Color = Tok.text2
    var body: some View {
        PixelBitmap(rows: [
            "....#..",
            "....#..",
            "....#..",
            ".......",
            ".......",
            "....#..",
            ".......",
        ], cell: cell, color: color)
    }
}

/// Wait cells: 3 cells, 2 pt cell, gap 4, pitch 6, stepping every 160 ms.
/// Reduce Motion renders the finished frame.
struct WaitCells: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var step = 0
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Rectangle()
                    .fill(reduceMotion ? Tok.accent : (i == step % 3 ? Tok.accent : Tok.controlPressed))
                    .frame(width: Pixel.snap(2), height: Pixel.snap(2))
            }
        }
        .onReceive(Timer.publish(every: 0.16, on: .main, in: .common).autoconnect()) { _ in step += 1 }
    }
}

/// Determinate tick meter: 3×10 ticks, gap 1, pitch 4, fills the track.
/// Filled ticks in Ramp.blue[3], tip white, empty slots as dust dots.
struct TickMeter: View {
    let fraction: Double
    var width: CGFloat = 120

    var body: some View {
        let count = max(1, Int(width / 4))
        let filled = Int((fraction * Double(count)).rounded())
        HStack(spacing: 1) {
            ForEach(0..<count, id: \.self) { i in
                if i < filled {
                    Rectangle()
                        .fill(i == filled - 1 && filled < count ? Tok.text : Ramp.blue[3])
                        .frame(width: Pixel.snap(3), height: Pixel.snap(10))
                } else {
                    // Dust: 1 pt dot in controlPressed — silence is dotted, never a slab.
                    Rectangle()
                        .fill(Tok.controlPressed)
                        .frame(width: Pixel.snap(1), height: Pixel.snap(1))
                        .frame(width: Pixel.snap(3), height: Pixel.snap(10))
                }
            }
        }
        .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.28), value: fraction)
        .accessibilityHidden(true)
    }
}

/// NotchedRect(step: 2): stepped corners, no radius, no stroke.
struct NotchedRect: Shape {
    var step: CGFloat = 2
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let s = step
        let w = rect.width
        let h = rect.height
        let points: [(CGFloat, CGFloat)] = [
            (rect.minX + s, rect.minY),
            (rect.maxX - s, rect.minY),
            (rect.maxX - s, rect.minY + s),
            (rect.maxX, rect.minY + s),
            (rect.maxX, rect.maxY - s),
            (rect.maxX - s, rect.maxY - s),
            (rect.maxX - s, rect.maxY),
            (rect.minX + s, rect.maxY),
            (rect.minX + s, rect.maxY - s),
            (rect.minX, rect.maxY - s),
            (rect.minX, rect.minY + s),
            (rect.minX + s, rect.minY + s),
        ]
        p.move(to: CGPoint(x: points[0].0, y: points[0].1))
        for pt in points.dropFirst() {
            p.addLine(to: CGPoint(x: pt.0, y: pt.1))
        }
        p.closeSubpath()
        _ = w
        _ = h
        return p
    }
}
