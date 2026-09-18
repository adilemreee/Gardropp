import SwiftUI

/// The hanger draws itself, settles with a small swing, and hands over to the app.
/// It picks up exactly where the static launch screen leaves off, so the launch
/// reads as one continuous moment rather than two screens.
struct SplashView: View {
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var drawn: CGFloat = 0
    @State private var swing: Double = 0
    @State private var wordmark = false
    @State private var isLeaving = false

    private let markSize: CGFloat = 190

    var body: some View {
        ZStack {
            Color.canvas.ignoresSafeArea()

            VStack(spacing: 18) {
                HangerMark()
                    .trim(from: 0, to: drawn)
                    .stroke(
                        Color.textPrimary,
                        style: StrokeStyle(
                            lineWidth: HangerMark.lineWidth(for: markSize),
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .frame(width: markSize, height: markSize)
                    .rotationEffect(.degrees(swing), anchor: HangerMark.pivot)

                VStack(spacing: 3) {
                    Text("Gardropp")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("YOUR PERSONAL STYLIST")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(1.6)
                        .foregroundStyle(Color.textSecondary)
                }
                .opacity(wordmark ? 1 : 0)
                .offset(y: wordmark ? 0 : 8)
            }
            .opacity(isLeaving ? 0 : 1)
            .scaleEffect(isLeaving ? 1.06 : 1)
        }
        .task { await play() }
    }

    private func play() async {
        guard !reduceMotion else {
            drawn = 1
            wordmark = true
            try? await Task.sleep(for: .seconds(0.7))
            withAnimation(.easeOut(duration: 0.3)) { isLeaving = true }
            try? await Task.sleep(for: .seconds(0.3))
            onFinished()
            return
        }

        withAnimation(.easeInOut(duration: 0.6)) { drawn = 1 }

        try? await Task.sleep(for: .seconds(0.38))
        withAnimation(.easeOut(duration: 0.35)) { wordmark = true }

        // A hanger just hung on the rail tips over and rocks itself straight:
        // a quick push out, then an underdamped spring back through centre.
        try? await Task.sleep(for: .seconds(0.24))
        withAnimation(.easeOut(duration: 0.13)) { swing = -7 }
        try? await Task.sleep(for: .seconds(0.13))
        withAnimation(.spring(response: 0.6, dampingFraction: 0.26)) { swing = 0 }

        try? await Task.sleep(for: .seconds(0.55))
        withAnimation(.easeIn(duration: 0.3)) { isLeaving = true }
        try? await Task.sleep(for: .seconds(0.3))
        onFinished()
    }
}

#Preview {
    SplashView {}
}
