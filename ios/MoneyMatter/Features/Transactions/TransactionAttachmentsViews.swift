import MoneyMatterKit
import PhotosUI
import QuickLook
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Limits and file preparation shared by the attachment pickers.
enum TransactionAttachmentFiles {
    static let maxBytes = 10 * 1024 * 1024
    static let maxPerTransaction = 10
    /// JPEG, PNG, WebP, and PDF are accepted by the server.
    static let importTypes: [UTType] = [.jpeg, .png, .webP, .pdf, .heic, .image]

    /// Photos arrive in many formats (often HEIC); anything that isn't JPEG, PNG, or WebP is
    /// re-encoded as JPEG.
    static func preparePhoto(_ data: Data, baseName: String) -> (filename: String, data: Data)? {
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return ("\(baseName).jpg", data) }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return ("\(baseName).png", data) }
        if data.count > 12, data[8..<12].elementsEqual(Array("WEBP".utf8)) { return ("\(baseName).webp", data) }
        guard let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.85) else { return nil }
        return ("\(baseName).jpg", jpeg)
    }

    static func photoBaseName() -> String {
        "Photo \(Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)))"
            .replacingOccurrences(of: ":", with: "-")
    }

    static var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
            && Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") != nil
    }
}

/// The add-attachment menu: Photos, Camera (when the device has one), and Files.
/// Hands back prepared files; the caller uploads or queues them.
struct TransactionAttachmentAddMenu: View {
    let onFiles: ([(filename: String, data: Data)]) -> Void
    let onError: (String) -> Void

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isPhotosPresented = false
    @State private var isCameraPresented = false
    @State private var isImporterPresented = false

    var body: some View {
        Menu {
            Button("Photo Library", systemImage: "photo.on.rectangle") { isPhotosPresented = true }
            if TransactionAttachmentFiles.isCameraAvailable {
                Button("Take Photo", systemImage: "camera") { isCameraPresented = true }
            }
            Button("Choose File", systemImage: "folder") { isImporterPresented = true }
        } label: {
            Label("Add Attachment", systemImage: "paperclip")
        }
        .photosPicker(isPresented: $isPhotosPresented, selection: $photoItems, maxSelectionCount: 5, matching: .images)
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await loadPhotos(items) }
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            TransactionCameraPicker { image in
                if let data = image.jpegData(compressionQuality: 0.85) {
                    deliver([("\(TransactionAttachmentFiles.photoBaseName()).jpg", data)])
                }
            }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.jpeg, .png, .webP, .pdf], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                deliver(urls.compactMap(readFile))
            case .failure:
                onError(String(localized: "The file couldn't be opened."))
            }
        }
    }

    private func readFile(_ url: URL) -> (filename: String, data: Data)? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (url.lastPathComponent, data)
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        var files: [(filename: String, data: Data)] = []
        for (index, item) in items.enumerated() {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let base = TransactionAttachmentFiles.photoBaseName() + (items.count > 1 ? " \(index + 1)" : "")
            if let file = TransactionAttachmentFiles.preparePhoto(data, baseName: base) { files.append(file) }
        }
        photoItems = []
        deliver(files)
    }

    private func deliver(_ files: [(filename: String, data: Data)]) {
        let tooBig = files.filter { $0.data.count > TransactionAttachmentFiles.maxBytes }
        if !tooBig.isEmpty {
            onError(String(localized: "Files can be at most 10 MB."))
        }
        let accepted = files.filter { $0.data.count <= TransactionAttachmentFiles.maxBytes }
        if !accepted.isEmpty { onFiles(accepted) }
    }
}

/// The attachments of a saved transaction: list, QuickLook preview, add, and delete.
struct TransactionAttachmentsSection: View {
    let transactionId: String
    var canEdit = true

    @Environment(AppServices.self) private var services
    @State private var state: LoadState<[TransactionAttachment]> = .idle
    @State private var uploadingCount = 0
    @State private var previewURL: URL?
    @State private var openingId: String?
    @State private var pendingDelete: TransactionAttachment?
    @State private var errorAlert: ErrorAlert?
    @State private var messageAlert: String?

    var body: some View {
        Section {
            switch state {
            case .idle, .loading:
                Label("Loading attachments", systemImage: "paperclip")
                    .redacted(reason: .placeholder)
            case .failed(let error):
                InlineRetryView(ErrorMessage.message(for: error)) { await load() }
            case .loaded(let attachments):
                if attachments.isEmpty, uploadingCount == 0 {
                    Text("No attachments")
                        .foregroundStyle(.secondary)
                }
                ForEach(attachments) { attachment in
                    row(attachment)
                }
            }
            if uploadingCount > 0 {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Uploading…")
                        .foregroundStyle(.secondary)
                }
            }
            if canEdit, (state.value?.count ?? 0) + uploadingCount < TransactionAttachmentFiles.maxPerTransaction, state.value != nil {
                TransactionAttachmentAddMenu { files in
                    Task { await upload(files) }
                } onError: { messageAlert = $0 }
            }
        } header: {
            Text("Attachments")
        }
        .task(id: transactionId) { await load() }
        .quickLookPreview($previewURL)
        .confirmationDialog(
            "Delete this attachment?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { attachment in
            Button("Delete Attachment", role: .destructive) {
                Task { await delete(attachment) }
            }
        } message: { attachment in
            Text(verbatim: attachment.filename)
        }
        .alert(
            "Couldn't Add Attachment",
            isPresented: Binding(get: { messageAlert != nil }, set: { if !$0 { messageAlert = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(messageAlert ?? "")
        }
        .errorAlert($errorAlert)
    }

    private func row(_ attachment: TransactionAttachment) -> some View {
        Button {
            Task { await open(attachment) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: attachment.isImage ? "photo" : "doc.richtext")
                    .foregroundStyle(.tint)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: attachment.filename)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(attachment.size.formatted(.byteCount(style: .file)))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if openingId == attachment.id {
                    ProgressView()
                }
            }
        }
        .disabled(openingId != nil)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if canEdit {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    pendingDelete = attachment
                }
            }
        }
        .contextMenu {
            if canEdit {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    pendingDelete = attachment
                }
            }
        }
    }

    private func load() async {
        guard let client = services.client else { return }
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await client.send(Endpoints.transactionAttachments(transactionId: transactionId)))
        } catch {
            let apiError = APIError(error)
            guard !apiError.isCancellation else { return }
            if state.value == nil { state = .failed(apiError) }
        }
    }

    private func upload(_ files: [(filename: String, data: Data)]) async {
        guard let client = services.client else { return }
        uploadingCount += files.count
        for file in files {
            do {
                let attachment = try await client.uploadTransactionAttachment(
                    TransactionAttachmentUpload(transactionId: transactionId, filename: file.filename, data: file.data)
                )
                state = .loaded((state.value ?? []) + [attachment])
            } catch {
                errorAlert = ErrorAlert(error)
            }
            uploadingCount -= 1
        }
        TransactionChangeFeed.shared.publish(.invalidated)
    }

    private func open(_ attachment: TransactionAttachment) async {
        guard let client = services.client else { return }
        openingId = attachment.id
        defer { openingId = nil }
        do {
            let data = try await client.downloadTransactionAttachment(id: attachment.id)
            let folder = FileManager.default.temporaryDirectory.appending(path: "attachments/\(attachment.id)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let safeName = attachment.filename.replacingOccurrences(of: "/", with: "-")
            let url = folder.appending(path: safeName.isEmpty ? "attachment" : safeName)
            try data.write(to: url, options: .atomic)
            previewURL = url
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }

    private func delete(_ attachment: TransactionAttachment) async {
        guard let client = services.client else { return }
        do {
            _ = try await client.send(Endpoints.deleteTransactionAttachment(id: attachment.id))
            state = .loaded((state.value ?? []).filter { $0.id != attachment.id })
            TransactionChangeFeed.shared.publish(.invalidated)
        } catch {
            errorAlert = ErrorAlert(error)
        }
    }
}

/// Files picked in the new-transaction sheet, uploaded once the transaction is saved.
struct TransactionPendingAttachmentsSection: View {
    @Bindable var model: TransactionEditorModel
    @State private var messageAlert: String?

    var body: some View {
        Section("Attachments") {
            ForEach(model.pendingAttachments) { file in
                HStack(spacing: 12) {
                    Image(systemName: file.filename.lowercased().hasSuffix(".pdf") ? "doc.richtext" : "photo")
                        .foregroundStyle(.tint)
                        .frame(width: 24)
                    Text(verbatim: file.filename)
                        .lineLimit(1)
                    Spacer()
                    Text(file.data.count.formatted(.byteCount(style: .file)))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .onDelete { model.pendingAttachments.remove(atOffsets: $0) }
            if model.pendingAttachments.count < TransactionAttachmentFiles.maxPerTransaction {
                TransactionAttachmentAddMenu { files in
                    model.pendingAttachments += files.map { .init(filename: $0.filename, data: $0.data) }
                } onError: { messageAlert = $0 }
            }
        }
        .alert(
            "Couldn't Add Attachment",
            isPresented: Binding(get: { messageAlert != nil }, set: { if !$0 { messageAlert = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(messageAlert ?? "")
        }
    }
}

/// The system camera, for photographing a receipt.
struct TransactionCameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: TransactionCameraPicker

        init(parent: TransactionCameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
