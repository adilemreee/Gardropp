@preconcurrency import AVFoundation
import Observation
import UIKit
import Vision

/// Drives the capture session for the scanner, and tells the UI when something
/// garment-shaped is actually in frame (the "Item detected" hint).
@MainActor
@Observable
final class CameraController: NSObject {

    enum Availability {
        case unknown, ready, denied, unavailable
    }

    private(set) var availability: Availability = .unknown
    private(set) var hasSubjectInFrame = false
    private(set) var isCapturing = false

    // The capture objects are only ever touched on `sessionQueue` (and by the
    // preview layer, which just needs the session reference), so they are safe
    // to reach from outside the main actor.
    nonisolated(unsafe) let session = AVCaptureSession()
    nonisolated(unsafe) private let photoOutput = AVCapturePhotoOutput()
    nonisolated(unsafe) private let videoOutput = AVCaptureVideoDataOutput()
    nonisolated private let sessionQueue = DispatchQueue(label: "com.gardropp.camera.session")
    nonisolated private let analysisQueue = DispatchQueue(label: "com.gardropp.camera.analysis")
    private var lastAnalysis = Date.distantPast
    private var photoContinuation: CheckedContinuation<UIImage?, Never>?

    func start() async {
        guard availability != .denied else { return }

        let granted = await AVCaptureDevice.requestAccess(for: .video)
        guard granted else {
            availability = .denied
            return
        }
        guard AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil else {
            // The simulator has no camera; the photo library path covers it.
            availability = .unavailable
            return
        }

        await withCheckedContinuation { continuation in
            let session = session
            let configure = makeConfiguration()
            sessionQueue.async {
                configure()
                if !session.isRunning { session.startRunning() }
                continuation.resume()
            }
        }
        availability = .ready
    }

    func stop() {
        let session = session
        sessionQueue.async {
            if session.isRunning { session.stopRunning() }
        }
    }

    /// Captures the configuration work as a closure the session queue can run.
    private nonisolated func makeConfiguration() -> @Sendable () -> Void {
        let session = session
        let photoOutput = photoOutput
        let videoOutput = videoOutput
        let delegate = self
        let queue = analysisQueue
        return {
            guard session.inputs.isEmpty else { return }
            session.beginConfiguration()
            session.sessionPreset = .photo

            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
               let input = try? AVCaptureDeviceInput(device: device),
               session.canAddInput(input) {
                session.addInput(input)
            }
            if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }

            videoOutput.setSampleBufferDelegate(delegate, queue: queue)
            videoOutput.alwaysDiscardsLateVideoFrames = true
            if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

            session.commitConfiguration()
        }
    }

    // MARK: - Capture

    func capturePhoto() async -> UIImage? {
        guard availability == .ready, !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }

        return await withCheckedContinuation { continuation in
            photoContinuation = continuation
            let output = photoOutput
            let delegate = self
            sessionQueue.async {
                let settings = AVCapturePhotoSettings()
                settings.flashMode = .off
                output.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }
}

// MARK: - Photo delegate

extension CameraController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let image = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
        Task { @MainActor in
            photoContinuation?.resume(returning: image?.normalizedOrientation())
            photoContinuation = nil
        }
    }
}

// MARK: - Live subject detection

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Saliency is cheap enough to run a few times a second.
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right)
        try? handler.perform([request])

        let area: CGFloat
        if let observation = request.results?.first,
           let object = observation.salientObjects?.first {
            area = object.boundingBox.width * object.boundingBox.height
        } else {
            area = 0
        }
        let detected = area > 0.12

        Task { @MainActor [weak self] in
            guard let self, Date.now.timeIntervalSince(lastAnalysis) > 0.35 else { return }
            lastAnalysis = .now
            if hasSubjectInFrame != detected { hasSubjectInFrame = detected }
        }
    }
}
