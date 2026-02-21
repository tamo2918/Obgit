//
//  ObgitApp.swift
//  Obgit
//

import SwiftUI
import Clibgit2

@main
struct ObgitApp: App {
    @AppStorage("app_appearance") private var appearanceRaw = 0
    @State private var showSplash = true

    init() {
        // libgit2 をスレッドセーフモードで初期化
        // アプリ起動時に一度だけ呼ぶ必要がある
        // 戻り値は libgit2 の参照カウント（正の値なら成功）
        let initResult = git_libgit2_init()
        assert(initResult > 0, "libgit2 の初期化に失敗しました: \(initResult)")
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                VaultHomeView()

                if showSplash {
                    SplashScreenView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .preferredColorScheme(resolvedColorScheme)
            .task {
                // 1.6秒後にスプラッシュをフェードアウト
                try? await Task.sleep(for: .seconds(1.6))
                withAnimation(.easeOut(duration: 0.45)) {
                    showSplash = false
                }
            }
        }
    }

    /// 0=system  1=light  2=dark
    private var resolvedColorScheme: ColorScheme? {
        switch appearanceRaw {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }
}

// MARK: - Splash Screen

private struct SplashScreenView: View {
    @State private var iconScale: CGFloat = 0.72
    @State private var iconOpacity: Double = 0

    var body: some View {
        ZStack {
            ObgitLiquidBackground()

            Image("icon")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 30, x: 0, y: 14)
                .scaleEffect(iconScale)
                .opacity(iconOpacity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.70)) {
                iconScale = 1.0
                iconOpacity = 1.0
            }
        }
    }
}
