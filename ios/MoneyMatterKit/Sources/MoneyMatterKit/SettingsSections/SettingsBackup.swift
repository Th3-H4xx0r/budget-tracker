import Foundation

/// The restore job's status from `GET /user/backup/restore/status/:jobId`.
public enum SettingsBackupJobStatus: String, LenientEnum, CaseIterable {
    case pending
    case processing
    case completed
    case failed
    case unknown

    public var isFinished: Bool { self == .completed || self == .failed }
}

/// Coarse restore phases reported while the job runs.
public enum SettingsBackupPhase: String, LenientEnum, CaseIterable {
    case validating
    case preparingSecurities = "preparing-securities"
    case wiping
    case restoring
    case finalizing
    case unknown
}

public struct SettingsBackupProgress: Sendable, Hashable, Decodable {
    public let phase: SettingsBackupPhase
    public let tier: Int?
    public let table: String?
    public let insertedRows: Int?

    public init(phase: SettingsBackupPhase, tier: Int? = nil, table: String? = nil, insertedRows: Int? = nil) {
        self.phase = phase
        self.tier = tier
        self.table = table
        self.insertedRows = insertedRows
    }

    private enum CodingKeys: String, CodingKey { case phase, tier, table, insertedRows }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        phase = (try? container.decodeIfPresent(SettingsBackupPhase.self, forKey: .phase)) ?? .unknown
        tier = try? container.decodeIfPresent(Int.self, forKey: .tier)
        table = try? container.decodeIfPresent(String.self, forKey: .table)
        insertedRows = try? container.decodeIfPresent(Int.self, forKey: .insertedRows)
    }
}

/// A non-fatal restore outcome, such as a skipped share or a reset settings row.
public struct SettingsBackupWarning: Sendable, Hashable, Decodable {
    public let code: String
    public let table: String?
    public let message: String
    public let count: Int?

    private enum CodingKeys: String, CodingKey { case code, table, message, count }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = (try? container.decodeIfPresent(String.self, forKey: .code)) ?? ""
        table = try? container.decodeIfPresent(String.self, forKey: .table)
        message = (try? container.decodeIfPresent(String.self, forKey: .message)) ?? ""
        count = try? container.decodeIfPresent(Int.self, forKey: .count)
    }
}

/// The finished restore: rows inserted per table, plus warnings.
public struct SettingsBackupSummary: Sendable, Hashable, Decodable {
    public let insertedByTable: [String: Int]
    public let warnings: [SettingsBackupWarning]

    public init(insertedByTable: [String: Int], warnings: [SettingsBackupWarning]) {
        self.insertedByTable = insertedByTable
        self.warnings = warnings
    }

    private enum CodingKeys: String, CodingKey { case insertedByTable, warnings }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        insertedByTable = (try? container.decodeIfPresent([String: Int].self, forKey: .insertedByTable)) ?? [:]
        warnings = (try? container.decodeIfPresent([SettingsBackupWarning].self, forKey: .warnings)) ?? []
    }

    /// Tables that received rows, biggest first.
    public var restoredTables: [SettingsBackupTableCount] {
        insertedByTable
            .filter { $0.value > 0 }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { SettingsBackupTableCount(table: $0.key, count: $0.value) }
    }

    /// `account_groups` / `account-groups` → `Account Groups`.
    public static func humanize(table: String) -> String {
        table
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

public struct SettingsBackupTableCount: Sendable, Hashable, Identifiable {
    public let table: String
    public let count: Int

    public var id: String { table }
}

/// `GET /user/backup/restore/status/:jobId`.
public struct SettingsBackupRestoreStatus: Sendable, Hashable, Decodable {
    public let jobId: String
    public let status: SettingsBackupJobStatus
    public let progress: SettingsBackupProgress?
    public let summary: SettingsBackupSummary?
    public let error: String?

    private enum CodingKeys: String, CodingKey { case jobId, status, progress, summary, error }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jobId = (try? container.decodeIfPresent(String.self, forKey: .jobId)) ?? ""
        status = (try? container.decodeIfPresent(SettingsBackupJobStatus.self, forKey: .status)) ?? .unknown
        progress = try? container.decodeIfPresent(SettingsBackupProgress.self, forKey: .progress)
        summary = try? container.decodeIfPresent(SettingsBackupSummary.self, forKey: .summary)
        error = try? container.decodeIfPresent(String.self, forKey: .error)
    }
}

/// `GET /user/backup/restore/status`: the user's in-flight restore, if any. Never 404s.
public struct SettingsBackupActiveRestore: Sendable, Hashable, Decodable {
    public enum State: String, LenientEnum, CaseIterable {
        case idle
        case queued
        case running
        case completed
        case failed
        case unknown
    }

    public let state: State
    public let jobId: String?
    public let phase: SettingsBackupPhase?
    public let insertedRows: Int?
    public let error: String?

    /// A restore is still queued or running, so the screen should resume polling it.
    public var isInFlight: Bool { (state == .queued || state == .running) && jobId != nil }

    private enum CodingKeys: String, CodingKey { case state, jobId, phase, insertedRows, error }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = (try? container.decodeIfPresent(State.self, forKey: .state)) ?? .unknown
        jobId = try? container.decodeIfPresent(String.self, forKey: .jobId)
        phase = try? container.decodeIfPresent(SettingsBackupPhase.self, forKey: .phase)
        insertedRows = try? container.decodeIfPresent(Int.self, forKey: .insertedRows)
        error = try? container.decodeIfPresent(String.self, forKey: .error)
    }
}

/// `POST /user/backup/restore` body: the zip as base64.
public struct SettingsBackupRestoreRequest: Encodable, Sendable, Hashable {
    public let fileContent: String
    /// Sent only after the user agreed that shared accounts and households lose access.
    public let acknowledgeSharing: Bool?

    public init(fileContent: String, acknowledgeSharing: Bool? = nil) {
        self.fileContent = fileContent
        self.acknowledgeSharing = acknowledgeSharing
    }
}

public struct SettingsBackupRestoreJob: Sendable, Hashable, Decodable {
    public let jobId: String
}

public enum SettingsBackupErrorCode {
    /// 409 from restore: the user owns shared resources and must acknowledge first.
    public static let sharingAcknowledgementRequired = "WIPE_DATA_SHARING_ACK_REQUIRED"
}

extension Endpoints {
    /// The backup filename when the server omits `Content-Disposition`.
    public static let settingsBackupDefaultFilename = "moneymatter-backup.zip"

    /// `POST /user/backup`: streams the full-data zip. Send with `APIClient.settingsDownload`.
    public static func settingsBackupExport() -> Endpoint<EmptyResponse> {
        Endpoint(.post, "/user/backup", body: EmptyBody())
    }

    /// `POST /user/backup/restore`: validates the zip, then queues the destructive restore.
    /// 422 means a bad or incompatible zip; 409 with `sharingAcknowledgementRequired` means
    /// the call must be repeated with `acknowledgeSharing: true`.
    public static func settingsBackupRestore(fileContent: String, acknowledgeSharing: Bool? = nil) -> Endpoint<String> {
        Endpoint<SettingsBackupRestoreJob>(
            .post,
            "/user/backup/restore",
            body: SettingsBackupRestoreRequest(fileContent: fileContent, acknowledgeSharing: acknowledgeSharing)
        )
        .map(\.jobId)
    }

    /// `GET /user/backup/restore/status/:jobId`.
    public static func settingsBackupRestoreStatus(jobId: String) -> Endpoint<SettingsBackupRestoreStatus> {
        let encoded = jobId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? jobId
        return Endpoint(.get, "/user/backup/restore/status/\(encoded)")
    }

    /// `GET /user/backup/restore/status`.
    public static func settingsBackupActiveRestore() -> Endpoint<SettingsBackupActiveRestore> {
        Endpoint(.get, "/user/backup/restore/status")
    }
}
