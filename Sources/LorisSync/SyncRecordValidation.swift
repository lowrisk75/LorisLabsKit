import Foundation

/// Outgoing content cannot be represented safely by this adapter's supported schema.
public enum CloudSyncValidationError: Error, Equatable, Sendable { case invalidRecord }
public enum CloudSyncSharePermissionError: Error, Equatable, Sendable { case existingPermissionMismatch }

enum SyncRecordValidation {
    // Deliberate supported subset, not an exhaustive statement about server schemas.
    // Validation happens before native record/field construction; no payload logging.
    static func validate(_ records: [SyncRecord]) throws {
        var identities = Set<Data>()
        for record in records {
            guard !record.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !record.id.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  validName(record.type), record.modifiedAt.timeIntervalSinceReferenceDate.isFinite else {
                throw CloudSyncValidationError.invalidRecord
            }
            guard identities.insert(Data(record.id.utf8)).inserted else {
                throw CloudSyncWriteError.invalidMutation
            }
            for (key, value) in record.fields {
                guard validName(key), !reservedFields.contains(key) else {
                    throw CloudSyncValidationError.invalidRecord
                }
                switch value {
                case .double(let number) where !number.isFinite:
                    throw CloudSyncValidationError.invalidRecord
                case .date(let date) where !date.timeIntervalSinceReferenceDate.isFinite:
                    throw CloudSyncValidationError.invalidRecord
                default: break
                }
            }
        }
    }
    private static let reservedFields: Set<String> = [
        "modifiedAt", "recordID", "recordType", "recordChangeTag", "creationDate", "modificationDate",
        "creatorUserRecordID", "lastModifiedUserRecordID", "parent", "share"
    ]
    private static func validName(_ value: String) -> Bool {
        let bytes = value.utf8
        guard let first = bytes.first, letter(first) else { return false }
        return bytes.allSatisfy { letter($0) || (48...57).contains($0) || $0 == 95 }
    }
    private static func letter(_ byte: UInt8) -> Bool {
        (65...90).contains(byte) || (97...122).contains(byte)
    }
    static func validateType(_ value: String) throws {
        guard validName(value) else { throw CloudSyncValidationError.invalidRecord }
    }
    static func validateID(_ value: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw CloudSyncValidationError.invalidRecord
        }
    }
}

extension SyncShareResolution {
    static func requirePermission(_ effective: SharePermission?, requested: SharePermission) throws {
        guard effective == requested else { throw CloudSyncSharePermissionError.existingPermissionMismatch }
    }
}
