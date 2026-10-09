import MoneyMatterKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Data › Backup & Restore: downloads a full-data zip to share, and restores one
/// picked from Files, polling the restore job until it lands.
struct BackupRestoreScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(ReferenceDataStore.self) private var referenceData

    @State private var backupFile: URL?
    @State private var isCreatingBackup = false
    @State private var importsFile = false
    @State private var pickedFile: PickedBackup?
    @State private var confirmsRestore = false
    @State private var confirmsSharing = false
    @State private var isSubmitting = false
    @State private var restore: RestoreProgress?
    @State private var pollingJobID: String?
    @State private var alert: ErrorAlert?

    var body: some View {
        Form {
            backupSection
            restoreSection
            if let restore {
                restoreProgressSection(restore)
            }
        }
        .navigationTitle("Backup & Restore")
        .fileImporter(isPresented: $importsFile, allowedContentTypes: [.zip]) { result in
            handlePicked(result)
        }
        .confirmationDialog(
            "Restore from this backup?",
            isPresented: $confirmsRestore,
            titleVisibility: .visible,
            presenting: pickedFile
        ) { _ in
            Button("Replace All Data", role: .destructive) {
                Task { await submitRestore(acknowledgeSharing: nil) }
            }
        } message: { file in
            Text("All current data is deleted and replaced with the contents of \(file.name). This can't be undone.")
        }
        .confirmationDialog(
            "Shared Data Will Lose Access",
            isPresented: $confirmsSharing,
            titleVisibility: .visible
        ) {
            Button("Restore Anyway", role: .destructive) {
                Task { await submitRestore(acknowledgeSharing: true) }
            }
        } message: {
            Text("You share accounts or a household with other people. Restoring removes their access to that data.")
        }
        .task { await resumeActiveRestore() }
        .task(id: pollingJobID) { await pollRestore() }
        .errorAlert($alert)
    }

    // MARK: Sections

    private var backupSection: some View {
        Section {
            Button {
                Task { await createBackup() }
            } label: {
                HStack {
                    Label("Create Backup", systemImage: "externaldrive.badge.plus")
                    Spacer()
                    if isCreatingBackup { ProgressView() }
                }
            }
            .disabled(isCreatingBackup || isRestoring)

            if let backupFile {
                ShareLink(item: backupFile) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Share Backup")
                            Text(backupFile.lastPathComponent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        } header: {
            Text("Backup")
        } footer: {
            Text("A backup is a zip of all your accounts, transactions, settings, and history. Keep it somewhere safe; it isn't encrypted.")
        }
    }

    private var restoreSection: some View {
        Section {
            Button {
                importsFile = true
            } label: {
                HStack {
                    Label("Restore from Backup…", systemImage: "arrow.counterclockwise")
                    Spacer()
                    if isSubmitting { ProgressView() }
                }
            }
            .disabled(isSubmitting || isRestoring || isCreatingBackup)
        } header: {
            Text("Restore")
        } footer: {
            Text("Restoring deletes everything in this account and replaces it with the backup. Bank connection credentials aren't part of a backup.")
        }
    }

    @ViewBuilder
    private func restoreProgressSection(_ restore: RestoreProgress) -> some View {
        switch restore {
        case .running(let phase, let insertedRows, let isUnconfirmed):
            Section("Restore in Progress") {
                HStack(spacing: 12) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.label(for: phase))
                        if let insertedRows, insertedRows > 0 {
                            Text("\(insertedRows) rows restored")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                if isUnconfirmed {
                    Text("Still waiting for the server. The restore keeps running; check back in a moment.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        case .completed(let summary):
            Section {
                Label("Restore Complete", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                ForEach(summary.restoredTables) { entry in
                    LabeledContent(SettingsBackupSummary.humanize(table: entry.table)) {
                        Text(entry.count, format: .number)
                            .monospacedDigit()
                    }
                }
            } header: {
                Text("Restored")
            }
            if !summary.warnings.isEmpty {
                Section("Warnings") {
                    ForEach(Array(summary.warnings.enumerated()), id: \.offset) { _, warning in
                        Label(warning.message, systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                    }
                }
            }
        case .failed(let message):
            Section("Restore Failed") {
                Label(message, systemImage: "xmark.octagon")
                    .foregroundStyle(.red)
                Text("Your previous data was kept.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var isRestoring: Bool {
        if case .running = restore { return true }
        return false
    }

    private static func label(for phase: SettingsBackupPhase?) -> String {
        switch phase {
        case .preparingSecurities: String(localized: "Preparing securities")
        case .wiping: String(localized: "Removing current data")
        case .restoring: String(localized: "Restoring data")
        case .finalizing: String(localized: "Finishing up")
        case .validating, .unknown, nil: String(localized: "Validating backup")
        }
    }

    // MARK: Actions

    private func createBackup() async {
        guard let client = services.client else { return }
        isCreatingBackup = true
        defer { isCreatingBackup = false }
        do {
            let download = try await client.settingsDownload(Endpoints.settingsBackupExport(), accept: "application/zip, application/json")
            let folder = FileManager.default.temporaryDirectory.appending(path: "backups", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appending(path: download.filename ?? Endpoints.settingsBackupDefaultFilename)
            try? FileManager.default.removeItem(at: url)
            try download.data.write(to: url, options: .atomic)
            backupFile = url
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private func handlePicked(_ result: Result<URL, any Error>) {
        switch result {
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                pickedFile = PickedBackup(name: url.lastPathComponent, base64: data.base64EncodedString())
                confirmsRestore = true
            } catch {
                alert = ErrorAlert(
                    title: String(localized: "Couldn't Open File"),
                    message: error.localizedDescription
                )
            }
        case .failure(let error):
            alert = ErrorAlert(error)
        }
    }

    private func submitRestore(acknowledgeSharing: Bool?) async {
        guard let client = services.client, let pickedFile else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let jobID = try await client.send(
                Endpoints.settingsBackupRestore(fileContent: pickedFile.base64, acknowledgeSharing: acknowledgeSharing)
            )
            restore = .running(phase: .validating, insertedRows: nil, isUnconfirmed: false)
            pollingJobID = jobID
        } catch let error as APIError {
            if case .server(409, let code, _) = error, code == SettingsBackupErrorCode.sharingAcknowledgementRequired {
                confirmsSharing = true
            } else {
                alert = ErrorAlert(error)
            }
        } catch {
            alert = ErrorAlert(error)
        }
    }

    private func resumeActiveRestore() async {
        guard let client = services.client, pollingJobID == nil,
              let active = try? await client.send(Endpoints.settingsBackupActiveRestore()),
              active.isInFlight, let jobID = active.jobId
        else { return }
        restore = .running(phase: active.phase, insertedRows: active.insertedRows, isUnconfirmed: false)
        pollingJobID = jobID
    }

    /// Polls every two seconds until the job finishes. A few failed polls in a row only mark
    /// the status unconfirmed: the restore keeps running on the server either way.
    private func pollRestore() async {
        guard let client = services.client, let jobID = pollingJobID else { return }
        var failures = 0
        while !Task.isCancelled {
            do {
                let status = try await client.send(Endpoints.settingsBackupRestoreStatus(jobId: jobID))
                failures = 0
                switch status.status {
                case .completed:
                    restore = .completed(status.summary ?? SettingsBackupSummary(insertedByTable: [:], warnings: []))
                    pollingJobID = nil
                    await referenceData.refresh()
                    return
                case .failed:
                    restore = .failed(status.error ?? String(localized: "The restore failed."))
                    pollingJobID = nil
                    return
                default:
                    restore = .running(phase: status.progress?.phase, insertedRows: status.progress?.insertedRows, isUnconfirmed: false)
                }
            } catch {
                if APIError(error).isCancellation { return }
                failures += 1
                if case .running(let phase, let rows, _) = restore, failures >= 3 {
                    restore = .running(phase: phase, insertedRows: rows, isUnconfirmed: true)
                }
            }
            try? await Task.sleep(for: .seconds(2))
        }
    }
}

private struct PickedBackup {
    let name: String
    let base64: String
}

private enum RestoreProgress {
    case running(phase: SettingsBackupPhase?, insertedRows: Int?, isUnconfirmed: Bool)
    case completed(SettingsBackupSummary)
    case failed(String)
}
