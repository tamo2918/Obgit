import SwiftUI

// MARK: - UIColor Adaptive Helper

private extension UIColor {
    /// ライト / ダーク 両対応カラーを1行で定義する
    static func adaptive(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? dark : light }
    }

    static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> UIColor {
        UIColor(red: r, green: g, blue: b, alpha: a)
    }
}

// MARK: - Palette

enum ObgitPalette {
    // アクセントカラー
    static let accent = Color(uiColor: .adaptive(
        light: .rgb(0.14, 0.50, 0.96),
        dark:  .rgb(0.35, 0.65, 1.00)
    ))
    static let accentSoft = Color(uiColor: .adaptive(
        light: .rgb(0.80, 0.91, 1.00),
        dark:  .rgb(0.10, 0.20, 0.42)
    ))
    static let mint = Color(uiColor: .adaptive(
        light: .rgb(0.22, 0.78, 0.67),
        dark:  .rgb(0.25, 0.84, 0.72)
    ))
    static let coral = Color(uiColor: .adaptive(
        light: .rgb(0.98, 0.56, 0.47),
        dark:  .rgb(1.00, 0.64, 0.54)
    ))
    static let violet = Color(uiColor: .adaptive(
        light: .rgb(0.62, 0.48, 0.96),
        dark:  .rgb(0.72, 0.58, 1.00)
    ))

    // テキスト
    static let ink = Color(uiColor: .adaptive(
        light: .rgb(0.15, 0.20, 0.28),
        dark:  .rgb(0.92, 0.94, 0.97)
    ))
    static let secondaryInk = Color(uiColor: .adaptive(
        light: .rgb(0.40, 0.46, 0.56),
        dark:  .rgb(0.58, 0.62, 0.72)
    ))

    // 背景グラデーション
    static let screenTop = Color(uiColor: .adaptive(
        light: .rgb(0.88, 0.94, 1.00),
        dark:  .rgb(0.07, 0.09, 0.15)
    ))
    static let screenBottom = Color(uiColor: .adaptive(
        light: .rgb(0.82, 0.84, 1.00),
        dark:  .rgb(0.09, 0.11, 0.20)
    ))

    // カード・パネル背景
    static let shellSurface = Color(uiColor: .adaptive(
        light: .white,
        dark:  .rgb(0.12, 0.14, 0.22)
    ))
    static let shellSurfaceStrong = Color(uiColor: .adaptive(
        light: .rgb(0.92, 0.96, 1.00),
        dark:  .rgb(0.08, 0.10, 0.18)
    ))
    static let sidebarSurface = Color(uiColor: .adaptive(
        light: .white,
        dark:  .rgb(0.10, 0.12, 0.20)
    ))

    // ボーダー・区切り線
    static let stroke = Color(uiColor: .adaptive(
        light: .white.withAlphaComponent(0.72),
        dark:  .white.withAlphaComponent(0.10)
    ))
    static let line = Color(uiColor: .adaptive(
        light: .rgb(0.75, 0.84, 0.90, 0.55),
        dark:  .white.withAlphaComponent(0.08)
    ))
}

// MARK: - Liquid Background

struct ObgitLiquidBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [ObgitPalette.screenTop, ObgitPalette.screenBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // 右上のハイライト（ダークでは大幅に弱める）
            RadialGradient(
                colors: [Color.white.opacity(colorScheme == .dark ? 0.04 : 0.85), .clear],
                center: .topTrailing,
                startRadius: 36,
                endRadius: 380
            )

            // 右下のバイオレットアクセント
            RadialGradient(
                colors: [ObgitPalette.violet.opacity(colorScheme == .dark ? 0.18 : 0.30), .clear],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 420
            )

            // 左下のミントグリーンのアクセント
            RadialGradient(
                colors: [ObgitPalette.mint.opacity(colorScheme == .dark ? 0.14 : 0.22), .clear],
                center: .bottomLeading,
                startRadius: 28,
                endRadius: 300
            )

            // 左上のブルーアクセント
            RadialGradient(
                colors: [ObgitPalette.accent.opacity(colorScheme == .dark ? 0.20 : 0.10), .clear],
                center: .topLeading,
                startRadius: 60,
                endRadius: 320
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Glass Card Modifier

private struct ObgitGlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                ObgitPalette.shellSurface,
                                ObgitPalette.shellSurfaceStrong.opacity(0.94)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(ObgitPalette.stroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.10), radius: 22, x: 0, y: 12)
    }
}

// MARK: - Icon Chip Modifier

private struct ObgitIconChipModifier: ViewModifier {
    let size: CGFloat
    let cornerRatio: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * cornerRatio, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                ObgitPalette.shellSurface,
                                ObgitPalette.shellSurfaceStrong.opacity(0.95)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * cornerRatio, style: .continuous)
                    .strokeBorder(ObgitPalette.stroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
    }
}

// MARK: - Glass Pill Button Style

struct ObgitGlassPillButtonStyle: ButtonStyle {
    var fillColor: Color = ObgitPalette.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(
                Capsule(style: .continuous)
                    .fill(fillColor.opacity(configuration.isPressed ? 0.18 : 0.26))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(ObgitPalette.stroke, lineWidth: 1)
            )
            .foregroundStyle(ObgitPalette.ink)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.80), value: configuration.isPressed)
    }
}

// MARK: - View Extensions

extension View {
    func obgitGlassCard(cornerRadius: CGFloat = 26) -> some View {
        modifier(ObgitGlassCardModifier(cornerRadius: cornerRadius))
    }

    func obgitIconChip(size: CGFloat = 42, cornerRatio: CGFloat = 0.35) -> some View {
        modifier(ObgitIconChipModifier(size: size, cornerRatio: cornerRatio))
    }

    func obgitScreenBackground() -> some View {
        background(ObgitLiquidBackground())
    }
}
