import AVFoundation
import SwiftUI

/// Camera mirror. The capture session exists only while this tab is visible.
struct MirrorView: View {
    @StateObject private var status = StateBox(AVCaptureDevice.authorizationStatus(for: .video))

    var body: some View {
        Group {
            switch status.value {
            case .authorized:
                CameraPreview()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            case .notDetermined:
                Color.clear.onAppear {
                    AVCaptureDevice.requestAccess(for: .video) { _ in
                        DispatchQueue.main.async { status.value = AVCaptureDevice.authorizationStatus(for: .video) }
                    }
                }
            default:
                VStack(spacing: 6) {
                    Image(systemName: "video.slash").font(.system(size: 24))
                    Text("Camera access is off. Enable it in System Settings › Privacy & Security › Camera.")
                        .font(.system(size: 12)).multilineTextAlignment(.center)
                }
                .foregroundStyle(.gray)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct CameraPreview: NSViewRepresentable {
    func makeNSView(context: Context) -> PreviewView { PreviewView() }
    func updateNSView(_ nsView: PreviewView, context: Context) {}
    static func dismantleNSView(_ nsView: PreviewView, coordinator: ()) { nsView.stop() }

    final class PreviewView: NSView {
        private let session = AVCaptureSession()
        private let queue = DispatchQueue(label: "opennotch.camera")

        init() {
            super.init(frame: .zero)
            wantsLayer = true
            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            preview.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1)) // mirror
            layer = preview
            queue.async { [session] in
                session.sessionPreset = .medium
                if let device = AVCaptureDevice.default(for: .video),
                   let input = try? AVCaptureDeviceInput(device: device),
                   session.canAddInput(input) {
                    session.addInput(input)
                }
                session.startRunning()
            }
        }

        required init?(coder: NSCoder) { fatalError() }

        func stop() {
            queue.async { [session] in session.stopRunning() }
        }
    }
}
