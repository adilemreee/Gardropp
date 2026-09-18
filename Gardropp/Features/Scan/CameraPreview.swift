import AVFoundation
import SwiftUI

/// Live camera feed, filling its frame.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if uiView.videoPreviewLayer.session !== session {
            uiView.videoPreviewLayer.session = session
        }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

/// The four corner brackets drawn over the viewfinder.
struct ViewfinderFrame: View {
    var isActive: Bool

    var body: some View {
        GeometryReader { proxy in
            let length = min(proxy.size.width, proxy.size.height) * 0.14
            ZStack {
                corner(length).position(x: 22, y: 22)
                corner(length).rotationEffect(.degrees(90)).position(x: proxy.size.width - 22, y: 22)
                corner(length).rotationEffect(.degrees(180)).position(x: proxy.size.width - 22, y: proxy.size.height - 22)
                corner(length).rotationEffect(.degrees(270)).position(x: 22, y: proxy.size.height - 22)
            }
            .foregroundStyle(.white.opacity(isActive ? 1 : 0.6))
            .animation(.easeInOut(duration: 0.25), value: isActive)
        }
    }

    private func corner(_ length: CGFloat) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: length))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: length, y: 0))
        }
        .stroke(style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        .frame(width: length, height: length)
    }
}
