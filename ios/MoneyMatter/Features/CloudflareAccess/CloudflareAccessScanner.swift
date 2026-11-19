import AVFoundation
import MoneyMatterKit
import SwiftUI
import Vision
import VisionKit

/// A sheet that scans the Cloudflare Access QR code from web Settings. The server's host is
/// shown for confirmation before the payload is handed back. With `expectedServer`, a code
/// for any other server is refused.
struct CloudflareAccessScanner: View {
    let expectedServer: ServerEndpoint?
    let onConfirm: (CloudflareAccessSetupPayload) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var pending: CloudflareAccessSetupPayload?
    @State private var rejection: String?
    @State private var startFailed = false
    /// Bumped when the app returns to the foreground, so camera permission and availability are read again.
    @State private var availabilityCheck = 0

    private var isScanning: Bool { pending == nil && rejection == nil }

    private var cameraDenied: Bool {
        _ = availabilityCheck
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        return status == .denied || status == .restricted
    }

    private var canScan: Bool {
        _ = availabilityCheck
        return DataScannerViewController.isSupported && DataScannerViewController.isAvailable && !startFailed
    }

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported, cameraDenied {
                    ContentUnavailableView {
                        Label("Camera access is off", systemImage: "camera.fill")
                    } description: {
                        Text("Allow camera access in Settings to scan the code, or paste the values instead.")
                    } actions: {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        .buttonStyle(.glassProminent)
                    }
                } else if canScan {
                    scanner
                } else {
                    ContentUnavailableView {
                        Label("Can't Scan", systemImage: "qrcode.viewfinder")
                    } description: {
                        Text("Scanning isn't available on this device. Paste the values instead.")
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            startFailed = false
            availabilityCheck += 1
        }
        .confirmationDialog(
            "Use this Cloudflare token?",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible,
            presenting: pending
        ) { payload in
            Button("Use Token") {
                onConfirm(payload)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: { payload in
            Text("For \(payload.server.hostAndPort)")
        }
    }

    private var scanner: some View {
        ZStack(alignment: .bottom) {
            QRCodeScannerView(isScanning: isScanning, onCode: handle, onFailure: { startFailed = true })
                .ignoresSafeArea(edges: .bottom)

            if let rejection {
                VStack(spacing: DS.Space.m) {
                    AuthBanner(message: rejection)
                    Button("Scan Again") { self.rejection = nil }
                        .buttonStyle(.glassProminent)
                }
                .padding()
                .background(.regularMaterial, in: .rect(cornerRadius: 20))
                .padding()
            }
        }
        .animation(.snappy, value: rejection)
    }

    private func handle(code: String) {
        do {
            let payload = try CloudflareAccessSetupPayload.parse(code)
            if let expectedServer, payload.server.hostAndPort != expectedServer.hostAndPort {
                let host = payload.server.hostAndPort
                rejection = String(localized: "That code is for \(host), not this server.")
                return
            }
            pending = payload
        } catch .insecureServer {
            rejection = String(localized: "That code points to a server without HTTPS.")
        } catch {
            rejection = String(localized: "That QR code isn't a MoneyMatter Cloudflare code.")
        }
    }
}

/// Camera preview that reports the first QR code, then stops until `isScanning` turns true again.
private struct QRCodeScannerView: UIViewControllerRepresentable {
    let isScanning: Bool
    let onCode: (String) -> Void
    let onFailure: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeUIViewController(context: Context) -> ScannerHostController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return ScannerHostController(scanner: scanner, wantsScanning: isScanning, onFailure: onFailure)
    }

    func updateUIViewController(_ controller: ScannerHostController, context: Context) {
        context.coordinator.onCode = onCode
        if isScanning, !context.coordinator.wasScanning { context.coordinator.hasReported = false }
        context.coordinator.wasScanning = isScanning
        controller.onFailure = onFailure
        controller.wantsScanning = isScanning
        controller.syncScanning()
    }

    /// Hosts the scanner as a child so scanning starts once the view is on screen.
    final class ScannerHostController: UIViewController {
        private let scanner: DataScannerViewController
        var wantsScanning: Bool
        var onFailure: () -> Void

        init(scanner: DataScannerViewController, wantsScanning: Bool, onFailure: @escaping () -> Void) {
            self.scanner = scanner
            self.wantsScanning = wantsScanning
            self.onFailure = onFailure
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func viewDidLoad() {
            super.viewDidLoad()
            addChild(scanner)
            scanner.view.frame = view.bounds
            scanner.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(scanner.view)
            scanner.didMove(toParent: self)
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            syncScanning()
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            if scanner.isScanning { scanner.stopScanning() }
        }

        func syncScanning() {
            guard view.window != nil else { return }
            if wantsScanning, !scanner.isScanning {
                do {
                    try scanner.startScanning()
                } catch {
                    // Reported on the next turn: this can run inside a SwiftUI view update.
                    DispatchQueue.main.async { [onFailure] in onFailure() }
                }
            } else if !wantsScanning, scanner.isScanning {
                scanner.stopScanning()
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCode: (String) -> Void
        var hasReported = false
        var wasScanning = false

        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !hasReported else { return }
            for case .barcode(let barcode) in addedItems {
                guard let value = barcode.payloadStringValue else { continue }
                hasReported = true
                dataScanner.stopScanning()
                onCode(value)
                return
            }
        }
    }
}
