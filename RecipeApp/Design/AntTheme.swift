import SwiftUI
import UIKit

/// Дизайн-токены в духе Ant Design 5 (ant.design): палитры, скругления, тени, отступы.
/// Значения — из стандартной темы Ant Design; тёмная тема — по их dark-алгоритму (упрощённо).
enum Ant {
    // MARK: Палитры (уровни 1, 3, 6, 7 из стандартных пресетов)

    struct Palette {
        let bg: Color      // уровень 1 — фон тега
        let border: Color  // уровень 3 — рамка тега
        let base: Color    // уровень 6 — основной цвет
        let text: Color    // уровень 7 — текст на светлом фоне

        init(_ c1: UInt32, _ c3: UInt32, _ c6: UInt32, _ c7: UInt32) {
            let base = UIColor(hex: c6)
            self.base = Color(base)
            bg = .dynamic(light: UIColor(hex: c1), dark: base.withAlphaComponent(0.16))
            border = .dynamic(light: UIColor(hex: c3), dark: base.withAlphaComponent(0.45))
            text = .dynamic(light: UIColor(hex: c7), dark: base.lighter(0.25))
        }
    }

    static let blue = Palette(0xE6F4FF, 0x91CAFF, 0x1677FF, 0x0958D9)
    static let green = Palette(0xF6FFED, 0xB7EB8F, 0x52C41A, 0x389E0D)
    static let red = Palette(0xFFF1F0, 0xFFA39E, 0xF5222D, 0xCF1322)
    static let volcano = Palette(0xFFF2E8, 0xFFBB96, 0xFA541C, 0xD4380D)
    static let orange = Palette(0xFFF7E6, 0xFFD591, 0xFA8C16, 0xD46B08)
    static let gold = Palette(0xFFFBE6, 0xFFE58F, 0xFAAD14, 0xD48806)
    static let magenta = Palette(0xFFF0F6, 0xFFADD2, 0xEB2F96, 0xC41D7F)
    static let cyan = Palette(0xE6FFFB, 0x87E8DE, 0x13C2C2, 0x08979C)
    static let purple = Palette(0xF9F0FF, 0xD3ADF7, 0x722ED1, 0x531DAB)
    static let geekblue = Palette(0xF0F5FF, 0xADC6FF, 0x2F54EB, 0x1D39C4)

    // MARK: Семантические цвета (colorPrimary, colorSuccess…)

    static let primary = Color(UIColor(hex: 0x1677FF))
    static let success = Color(UIColor(hex: 0x52C41A))
    static let warning = Color(UIColor(hex: 0xFAAD14))
    static let error = Color(UIColor(hex: 0xFF4D4F))

    /// colorBgLayout — фон экрана
    static let bgLayout = Color.dynamic(light: UIColor(hex: 0xF5F5F5), dark: UIColor(hex: 0x000000))
    /// colorBgContainer — фон карточек
    static let bgContainer = Color.dynamic(light: .white, dark: UIColor(hex: 0x141414))
    /// colorFillTertiary — заливка неактивных элементов
    static let fill = Color.dynamic(light: UIColor(white: 0, alpha: 0.04), dark: UIColor(white: 1, alpha: 0.08))
    /// colorBorderSecondary — тонкие разделители и рамки карточек
    static let borderSecondary = Color.dynamic(light: UIColor(hex: 0xF0F0F0), dark: UIColor(hex: 0x303030))
    /// colorBorder
    static let border = Color.dynamic(light: UIColor(hex: 0xD9D9D9), dark: UIColor(hex: 0x424242))

    static let text = Color.dynamic(light: UIColor(white: 0, alpha: 0.88), dark: UIColor(white: 1, alpha: 0.85))
    static let textSecondary = Color.dynamic(light: UIColor(white: 0, alpha: 0.65), dark: UIColor(white: 1, alpha: 0.65))
    static let textTertiary = Color.dynamic(light: UIColor(white: 0, alpha: 0.45), dark: UIColor(white: 1, alpha: 0.45))

    // MARK: Размеры (borderRadius 6 / LG 8, сетка отступов 4)

    static let radiusSM: CGFloat = 4
    static let radius: CGFloat = 6
    static let radiusLG: CGFloat = 8
    static let padding: CGFloat = 16
    static let paddingSM: CGFloat = 12
    static let paddingXS: CGFloat = 8

    /// Палитра рубрики — для тегов и акцентов.
    static func palette(forRubric id: String) -> Palette {
        switch id {
        case "breakfast": return gold
        case "soup": return volcano
        case "salad": return green
        case "main": return orange
        case "side": return cyan
        case "pastry": return magenta
        default: return blue
        }
    }
}

// MARK: - Тени (boxShadowTertiary — карточки, boxShadowSecondary — всплывающее)

extension View {
    /// Карточка Ant Design: фон контейнера, скругление LG, тонкая рамка и мягкая тень.
    func antCard(padding: CGFloat? = Ant.paddingSM, radius: CGFloat = Ant.radiusLG) -> some View {
        self
            .padding(padding ?? 0)
            .background(Ant.bgContainer, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Ant.borderSecondary))
            .antShadow()
    }

    func antShadow(elevated: Bool = false) -> some View {
        self
            .shadow(color: .black.opacity(elevated ? 0.08 : 0.03), radius: elevated ? 8 : 1, y: elevated ? 6 : 1)
            .shadow(color: .black.opacity(elevated ? 0.05 : 0.02), radius: elevated ? 14 : 3, y: elevated ? 9 : 2)
    }
}

// MARK: - Компоненты

/// Tag: маленькая плашка с рамкой, как `<Tag color="orange">`.
struct AntTag: View {
    let text: String
    var palette: Ant.Palette = Ant.blue
    var systemImage: String? = nil
    var bordered = true

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage { Image(systemName: systemImage).imageScale(.small) }
            Text(text)
        }
        .font(.caption2.weight(.medium))
        .lineLimit(1)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .foregroundStyle(palette.text)
        .background(palette.bg, in: RoundedRectangle(cornerRadius: Ant.radiusSM, style: .continuous))
        .overlay {
            if bordered {
                RoundedRectangle(cornerRadius: Ant.radiusSM, style: .continuous).strokeBorder(palette.border, lineWidth: 0.75)
            }
        }
    }
}

/// CheckableTag / Segmented: переключаемые плашки рубрик.
struct AntCheckableTag<Icon: View>: View {
    let title: String
    let selected: Bool
    @ViewBuilder var icon: () -> Icon
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                icon()
                Text(title)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(selected ? Color.white : Ant.text)
            .background {
                RoundedRectangle(cornerRadius: Ant.radius, style: .continuous)
                    .fill(selected ? Ant.primary : Ant.bgContainer)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Ant.radius, style: .continuous)
                    .strokeBorder(selected ? Color.clear : Ant.border, lineWidth: 1)
            }
        }
        .buttonStyle(AntPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Кнопка Ant: primary (заливка) или default (рамка).
struct AntButtonStyle: ButtonStyle {
    enum Kind { case primary, `default`, dashed }
    var kind: Kind = .primary
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 40)
            .padding(.horizontal, 15)
            .foregroundStyle(kind == .primary ? Color.white : Ant.primary)
            .background {
                let shape = RoundedRectangle(cornerRadius: Ant.radiusLG, style: .continuous)
                switch kind {
                case .primary:
                    shape.fill(Ant.primary.opacity(configuration.isPressed ? 0.8 : 1))
                        .shadow(color: Ant.primary.opacity(0.25), radius: 0, y: 2)
                case .default:
                    shape.fill(Ant.bgContainer).overlay(shape.strokeBorder(Ant.primary.opacity(0.6)))
                case .dashed:
                    shape.fill(Ant.bgContainer)
                        .overlay(shape.strokeBorder(Ant.primary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                }
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Лёгкое «нажатие» для карточек и плашек.
struct AntPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Заголовок раздела в стиле `Typography.Title level={4}` с необязательной подписью справа.
struct AntSectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(Ant.text)
            Spacer()
            trailing()
        }
    }
}

extension AntSectionHeader where Trailing == EmptyView {
    init(title: String) { self.init(title: title) { EmptyView() } }
}

/// Steps (вертикальные): номер в круге и линия к следующему шагу.
struct AntSteps: View {
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 4) {
                        Text("\(index + 1)")
                            .font(.footnote.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Ant.primary, in: Circle())
                        if index < steps.count - 1 {
                            Rectangle().fill(Ant.border).frame(width: 1).frame(maxHeight: .infinity)
                        }
                    }
                    Text(step)
                        .font(.body)
                        .foregroundStyle(Ant.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 3)
                        .padding(.bottom, index < steps.count - 1 ? 16 : 0)
                    Spacer(minLength: 0)
                }
                .appear(index: index)
            }
        }
    }
}

// MARK: - Цвета

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    func lighter(_ amount: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return UIColor(hue: h, saturation: max(0, s - amount * 0.5), brightness: min(1, b + amount), alpha: a)
    }
}

extension Color {
    static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}
