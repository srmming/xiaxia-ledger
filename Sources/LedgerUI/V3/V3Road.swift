#if os(macOS)
import FinanceCore
import SwiftUI

/// 目标的路：一条弯弯的路，上面几站。走过的站打勾、带一封信；正要去的那站是金色星星；夏夏站在你走到的地方。
struct V3Road: View {
    let journey: Journey
    /// 小号：总览卡片里用，只画路和金额。
    var mini = false
    /// 每站下面的小字（日期、「这一站」）。
    var captions: [Int: String] = [:]
    var endEmoji = "💻"
    var markerText = "你在这儿"
    var accent: Color = V3.navy
    /// 点了路上第几站的信封（走过的站才有）。
    var onLetter: ((Int) -> Void)?

    var body: some View {
        let pos = journey.position
        let f = V3RoadGeometry.fraction(passed: pos.passed, within: pos.fraction, count: journey.stations.count)
        GeometryReader { g in
            // 大号的路按卡片的高矮拉长，铺满，不在上面留一大片空
            let tall = mini ? 350 : min(max(620 * g.size.height / max(g.size.width, 1), 400), 700)
            V3Fit(design: CGSize(width: 620, height: tall)) {
                ZStack {
                    V3RoadCanvas(walk: journey.isFinished ? 1 : f, journey: journey, mini: mini, captions: captions,
                                 endEmoji: endEmoji, markerText: markerText, accent: accent, tall: mini ? 400 : tall)
                        .animation(.spring(duration: 0.7), value: f)
                    // 走过的站上那封信：点得开
                    if !mini, let onLetter {
                        let n = journey.stations.count
                        ForEach(Array(journey.stations.enumerated()), id: \.element.id) { i, st in
                            if i > 0, st.target <= journey.saved {
                                let p = V3RoadGeometry.point(at: V3RoadGeometry.stationFraction(i, count: n))
                                let y = 90 + (p.y - 55) * (tall - 145) / 290
                                Button { onLetter(i) } label: { Color.clear.frame(width: 40, height: 34).contentShape(Rectangle()) }
                                    .buttonStyle(.plain).position(x: p.x, y: y - 35)
                                    .help("打开这一站的信").accessibilityLabel("第 \(i) 站的信")
                            }
                        }
                    }
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(journey.name)的路")
        .accessibilityValue("已存 \(journey.saved.v3Short)，一共 \(journey.total.v3Short)，到下一站还差 \(journey.remainingToNext.v3Short)")
    }
}

enum V3RoadGeometry {
    /// 设计稿里那条路（620×400 的画布）。五段曲线，每段的终点是一站。
    static let points: [CGPoint] = [CGPoint(x: 50, y: 345), CGPoint(x: 170, y: 300), CGPoint(x: 290, y: 250),
                                    CGPoint(x: 400, y: 175), CGPoint(x: 500, y: 110), CGPoint(x: 585, y: 55)]
    private static let controls: [(CGPoint, CGPoint)] = [
        (CGPoint(x: 110, y: 345), CGPoint(x: 120, y: 300)),
        (CGPoint(x: 220, y: 300), CGPoint(x: 240, y: 250)),
        (CGPoint(x: 340, y: 250), CGPoint(x: 350, y: 175)),
        (CGPoint(x: 450, y: 175), CGPoint(x: 450, y: 110)),
        (CGPoint(x: 550, y: 110), CGPoint(x: 550, y: 55)),
    ]

    static let path: Path = {
        var p = Path()
        p.move(to: points[0])
        for i in 0..<5 { p.addCurve(to: points[i + 1], control1: controls[i].0, control2: controls[i].1) }
        return p
    }()

    /// 每段终点在整条路上的位置（0…1，按路的长度）。
    static let segmentEnds: [Double] = {
        var lengths: [Double] = []
        for i in 0..<5 {
            var len = 0.0
            var prev = points[i]
            for k in 1...24 {
                let t = Double(k) / 24
                let q = cubic(points[i], controls[i].0, controls[i].1, points[i + 1], t)
                len += hypot(q.x - prev.x, q.y - prev.y)
                prev = q
            }
            lengths.append(len)
        }
        let total = lengths.reduce(0, +)
        var acc = 0.0
        return [0] + lengths.map { acc += $0; return acc / total }
    }()

    private static func cubic(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint, _ t: Double) -> CGPoint {
        let u = 1 - t
        let x = u * u * u * a.x + 3 * u * u * t * b.x + 3 * u * t * t * c.x + t * t * t * d.x
        let y = u * u * u * a.y + 3 * u * u * t * b.y + 3 * u * t * t * c.y + t * t * t * d.y
        return CGPoint(x: x, y: y)
    }

    /// 第 i 站在路上的位置。正好 6 站就用设计稿的位置，别的站数平均摆。
    static func stationFraction(_ i: Int, count: Int) -> Double {
        guard count > 1 else { return 0 }
        if count == 6 { return segmentEnds[min(max(i, 0), 5)] }
        return Double(i) / Double(count - 1)
    }

    static func fraction(passed: Int, within: Double, count: Int) -> Double {
        let a = stationFraction(passed, count: count)
        let b = stationFraction(min(passed + 1, count - 1), count: count)
        return a + (b - a) * within
    }

    static func point(at f: Double) -> CGPoint {
        if f <= 0.0001 { return points[0] }
        return path.trimmedPath(from: 0, to: min(f, 1)).currentPoint ?? points[0]
    }
}

private struct V3RoadCanvas: View, Animatable {
    var walk: Double
    let journey: Journey
    let mini: Bool
    let captions: [Int: String]
    let endEmoji: String
    let markerText: String
    let accent: Color
    /// 画布有多高。比 400 高时，路在竖直方向拉长（站和字不变形）。
    var tall: CGFloat = 400

    var animatableData: Double {
        get { walk }
        set { walk = newValue }
    }

    var body: some View {
        Canvas { ctx, _ in
            if mini { ctx.translateBy(x: -8, y: -14) }
            let ink = GraphicsContext.Shading.color(V3.ink)
            // 顶上留 90、底下留 55，中间那段按高度拉长
            let k = (tall - 145) / 290
            let lift = CGAffineTransform(translationX: 0, y: 90).scaledBy(x: 1, y: k).translatedBy(x: 0, y: -55)
            func at(_ t: Double) -> CGPoint { V3RoadGeometry.point(at: t).applying(lift) }
            let path = tall == 400 ? V3RoadGeometry.path : V3RoadGeometry.path.applying(lift)
            if !mini {
                // 云、星星、远处的小山
                let up = tall / 400
                for (x, y, rx, ry) in [(120.0, 90.0 * up, 46.0, 15.0), (150, 78 * up, 30, 14), (320, 50 * up, 40, 12)] {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - rx, y: y - ry, width: rx * 2, height: ry * 2)), with: .color(.white.opacity(0.9)))
                }
                for (x, y) in [(236.0, 124.0 * up), (461, 39 * up), (76, 174 * up)] {
                    ctx.draw(Text("★").font(.system(size: 18)).foregroundColor(V3.ink), at: CGPoint(x: x, y: y))
                    ctx.draw(Text("★").font(.system(size: 16)).foregroundColor(V3.star), at: CGPoint(x: x, y: y))
                }
            }
            // 路：浅色底、白虚线、走过的那段深色
            ctx.stroke(path, with: .color(V3.soft), style: StrokeStyle(lineWidth: 24, lineCap: .round))
            ctx.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [2, 14]))
            if walk > 0.001 {
                ctx.stroke(path.trimmedPath(from: 0, to: min(walk, 1)), with: .color(accent), style: StrokeStyle(lineWidth: 9, lineCap: .round))
            }
            // 每一站
            let n = journey.stations.count
            let next = journey.isFinished ? -1 : journey.nextIndex
            for (i, st) in journey.stations.enumerated() {
                let p = tall == 400 ? V3RoadGeometry.point(at: V3RoadGeometry.stationFraction(i, count: n)) : at(V3RoadGeometry.stationFraction(i, count: n))
                let reached = st.target <= journey.saved
                let isNext = i == next
                let r: CGFloat = isNext ? 15 : 11
                let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                ctx.fill(dot, with: .color(reached ? accent : isNext ? V3.goodBG : .white))
                ctx.stroke(dot, with: ink, lineWidth: 3)
                if reached {
                    var tick = Path()
                    tick.move(to: CGPoint(x: p.x - 5, y: p.y)); tick.addLine(to: CGPoint(x: p.x - 1, y: p.y + 4)); tick.addLine(to: CGPoint(x: p.x + 6, y: p.y - 4))
                    ctx.stroke(tick, with: .color(.white), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                } else if isNext {
                    ctx.draw(Text("★").font(.system(size: 14)).foregroundColor(V3.gold), at: p)
                }
                if i == n - 1 { ctx.draw(Text(endEmoji).font(.system(size: 26)), at: CGPoint(x: p.x, y: p.y - (mini ? 27 : 32))) }
                if !mini || i > 0 {
                    let label = i == 0 ? "出发" : st.target.v3Short
                    let text = ctx.resolve(Text(label).font(.system(size: mini ? 24 : 15, weight: .heavy, design: .rounded))
                        .foregroundColor(reached || isNext ? V3.ink : V3.ink2))
                    let half = text.measure(in: CGSize(width: 400, height: 60)).width / 2
                    // 最右边那站的字别画出去
                    ctx.draw(text, at: CGPoint(x: min(p.x, 624 - half), y: p.y + (mini ? 34 : 29)))
                    if !mini, let c = captions[i], !c.isEmpty {
                        ctx.draw(Text(c).font(.system(size: 12, weight: isNext ? .heavy : .medium))
                            .foregroundColor(isNext ? V3.gold : V3.ink2), at: CGPoint(x: p.x, y: p.y + 47))
                    }
                }
                // 走过的站带一封信
                if !mini, reached, i > 0 {
                    let box = CGRect(x: p.x - 13, y: p.y - 44, width: 26, height: 18)
                    let env = Path(roundedRect: box, cornerRadius: 3)
                    ctx.fill(env, with: .color(V3.paper)); ctx.stroke(env, with: ink, lineWidth: 2)
                    var flap = Path()
                    flap.move(to: CGPoint(x: box.minX + 1, y: box.minY + 2)); flap.addLine(to: CGPoint(x: box.midX, y: box.minY + 11))
                    flap.addLine(to: CGPoint(x: box.maxX - 1, y: box.minY + 2))
                    ctx.stroke(flap, with: ink, lineWidth: 2)
                }
            }
            // 夏夏站在走到的地方
            let here = tall == 400 ? V3RoadGeometry.point(at: walk) : at(walk)
            let c = CGPoint(x: here.x, y: here.y - (mini ? 46 : 50))
            let ring = Path(ellipseIn: CGRect(x: c.x - 21, y: c.y - 21, width: 42, height: 42))
            ctx.fill(ring, with: .color(.white)); ctx.stroke(ring, with: ink, lineWidth: 3)
            ctx.draw(V3.image("head-happy"), in: CGRect(x: c.x - 22, y: c.y - 19, width: 44, height: 38))
            if !mini {
                ctx.draw(Text(markerText).font(.system(size: 12, weight: .heavy)).foregroundColor(accent), at: CGPoint(x: c.x, y: c.y - 31))
            }
        }
    }
}
#endif
