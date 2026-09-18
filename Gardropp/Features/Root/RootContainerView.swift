import SwiftUI

/// Holds the launch animation over the app until it has played out.
struct RootContainerView: View {
    @State private var showsSplash = true

    var body: some View {
        ZStack {
            RootTabView()

            if showsSplash {
                SplashView { showsSplash = false }
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
    }
}
