import SwiftUI

/// Анимации по мотивам reactbits.dev, переписанные на SwiftUI:
/// FadeContent/AnimatedContent, CountUp, BlurText, ShinyText, ClickSpark, Aurora и наклон карточек в карусели.
/// Все учитывают системную настройку «Уменьшение движения».
enum Motion {
    /// В UI-тестах бесконечные анимации выключены, чтобы приложение «успокаивалось» к скриншоту.
    static let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")
}

// MARK: - FadeContent / AnimatedContent: появление снизу с размытием

private struct AppearModifier: ViewModifier {
    let delay: Double
    var distance: CGFloat = 18
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : distance)
            .blur(radius: shown || reduceMotion ? 0 : 6)
            .onAppear {
                guard !shown else { return }
                if reduceMotion {
                    withAnimation(.easeOut(duration: 0.2)) { shown = true }
                } else {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.82).delay(delay)) { shown = true }
                }
            }
    }
}

extension View {
    /// Плавное появление; `index` даёт «лесенку» для списков и сеток.
    func appear(index: Int = 0, step: Double = 0.05, maxDelay: Double = 0.4) -> some View {
        modifier(AppearModifier(delay: min(Double(index) * step, maxDelay)))
    }
}

// MARK: - CountUp: число «добегает» до значения

struct CountUp: View, Animatable {
    var value: Double
    var font: Font = .title3.weight(.bold)

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text("\(Int(value.rounded()))")
            .font(font.monospacedDigit())
    }
}

/// Обёртка: стартует с нуля при первом показе и анимирует изменения.
struct CountUpText: View {
    let value: Double
    var font: Font = .title3.weight(.bold)
    var duration: Double = 0.9
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    var body: some View {
        CountUp(value: shown, font: font)
            .onAppear { animate(to: value) }
            .onChange(of: value) { _, new in animate(to: new) }
            .accessibilityLabel("\(Int(value.rounded()))")
    }

    private func animate(to target: Double) {
        if reduceMotion { shown = target; return }
        withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: duration)) { shown = target }
    }
}

// MARK: - BlurText: слова проявляются по очереди из размытия

struct BlurText: View {
    let text: String
    var font: Font = .largeTitle.weight(.bold)
    var delayPerWord: Double = 0.08
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private var words: [String] { text.split(separator: " ").map(String.init) }

    var body: some View {
        WrapLayout(spacing: 0, lineSpacing: 2) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                Text(index < words.count - 1 ? word + " " : word)
                    .font(font)
                    .opacity(shown ? 1 : 0)
                    .blur(radius: shown || reduceMotion ? 0 : 8)
                    .offset(y: shown || reduceMotion ? 0 : -10)
                    .animation(reduceMotion ? .easeOut(duration: 0.2)
                               : .easeOut(duration: 0.5).delay(Double(index) * delayPerWord), value: shown)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.isHeader)
        .onAppear { shown = true }
    }
}

/// Простой перенос слов по строкам.
struct WrapLayout: Layout {
    var spacing: CGFloat = 0
    var lineSpacing: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal: proposal, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + CGFloat(max(rows.count - 1, 0)) * lineSpacing
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + row.height - size.height), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = [Row()]
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if rows[rows.count - 1].width + size.width > maxWidth, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += size.width + spacing
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}

// MARK: - ShinyText: блик пробегает по тексту

struct ShinyText: View {
    let text: String
    var font: Font = .caption.weight(.medium)
    var color: Color = Ant.textTertiary
    var speed: Double = 2.6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .overlay {
                if !reduceMotion && !Motion.isUITesting {
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, .white.opacity(0.9), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.5)
                            .offset(x: phase * geo.size.width * 1.5)
                    }
                    .mask(Text(text).font(font))
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                guard !reduceMotion && !Motion.isUITesting else { return }
                withAnimation(.linear(duration: speed).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

// MARK: - ClickSpark: искры при нажатии

private struct SparkBurst: View {
    let trigger: Int
    var color: Color
    var count = 8
    var radius: CGFloat = 22
    @State private var progress: CGFloat = 1

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                let angle = Double(i) / Double(count) * 2 * .pi
                Capsule()
                    .fill(color)
                    .frame(width: 2.5, height: 7 * (1 - progress) + 1)
                    .offset(y: -(8 + radius * progress))
                    .rotationEffect(.radians(angle))
                    .opacity(progress >= 1 ? 0 : 1 - Double(progress))
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in
            progress = 0
            withAnimation(.easeOut(duration: 0.45)) { progress = 1 }
        }
    }
}

extension View {
    /// Искры вокруг элемента каждый раз, когда меняется `trigger`.
    func clickSpark(trigger: Int, color: Color = Ant.red.base) -> some View {
        overlay { SparkBurst(trigger: trigger, color: color) }
    }
}

// MARK: - Aurora: медленно плывущие цветные пятна

struct AuroraBackground: View {
    var colors: [Color] = [Ant.blue.base, Ant.cyan.base, Ant.purple.base]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion || Motion.isUITesting {
            canvas(time: 2.4)
        } else {
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                canvas(time: context.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func canvas(time t: Double) -> some View {
        Canvas { ctx, size in
            ctx.addFilter(.blur(radius: min(size.width, size.height) * 0.22))
            let blobs: [(Double, Double, Double)] = [(0.25, 0.30, 0.0), (0.75, 0.35, 2.1), (0.5, 0.85, 4.2)]
            for (index, blob) in blobs.enumerated() {
                let x = (blob.0 + 0.18 * sin(t * 0.35 + blob.2)) * size.width
                let y = (blob.1 + 0.20 * cos(t * 0.28 + blob.2)) * size.height
                let r = size.width * 0.42
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r * 0.7, width: r * 2, height: r * 1.4)),
                         with: .color(colors[index % colors.count].opacity(0.75)))
            }
        }
    }
}

// MARK: - Карусель с наклоном (TiltedCard/Carousel): карточки поворачиваются у краёв

extension View {
    func carouselTilt() -> some View {
        scrollTransition(.interactive, axis: .horizontal) { content, phase in
            content
                .rotation3DEffect(.degrees(phase.value * -14), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                .scaleEffect(1 - abs(phase.value) * 0.06)
                .opacity(1 - abs(phase.value) * 0.25)
        }
    }
}
