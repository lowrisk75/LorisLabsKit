#if canImport(CloudKit)
import CloudKit
import Foundation

/// Mapping between `SyncValue` and CloudKit field values.
///
/// Kept in its own file so the model stays CloudKit-free and testable: everything
/// above `CloudKitDatabase` deals in `SyncValue`, never `CKRecordValue`.
extension SyncValue {

    /// CloudKit representation, or `nil` when the value cannot be stored as-is.
    var ckValue: CKRecordValue {
        switch self {
        case .string(let v):     return v as CKRecordValue
        case .int(let v):        return v as CKRecordValue
        case .double(let v):     return v as CKRecordValue
        case .bool(let v):       return (v ? 1 : 0) as CKRecordValue   // CloudKit has no Bool
        case .date(let v):       return v as CKRecordValue
        case .data(let v):       return v as CKRecordValue
        case .stringList(let v): return v as CKRecordValue
        case .intList(let v):    return v as CKRecordValue
        }
    }

    /// Read a CloudKit value back.
    ///
    /// CloudKit stores booleans as numbers, so a round-trip cannot tell `true` from
    /// `1`. The app knows which its schema means, so `Int` is returned and callers
    /// use `record.bool(_:)` only on fields they wrote as booleans — guessing here
    /// would silently corrupt integer fields holding 0 or 1.
    static func from(_ value: Any) -> SyncValue? {
        switch value {
        case let v as String:   return .string(v)
        case let v as Date:     return .date(v)
        case let v as Data:     return .data(v)
        case let v as [String]: return .stringList(v)
        case let v as [Int]:    return .intList(v)
        case let v as NSNumber:
            // Distinguish integral from fractional; `NSNumber` erases the original.
            let d = v.doubleValue
            return d == d.rounded() && abs(d) < 9e15 ? .int(v.intValue) : .double(d)
        default:
            return nil
        }
    }
}

extension SyncRecord {

    /// Populate a `CKRecord` from this record's typed fields.
    func apply(to record: CKRecord, modifiedKey: String) {
        for (key, value) in fields {
            record[key] = value.ckValue
        }
        record[modifiedKey] = modifiedAt as CKRecordValue
    }

    /// Build from a `CKRecord`, keeping every field the schema carries.
    init?(from record: CKRecord, type: String, modifiedKey: String) {
        guard let modified = record[modifiedKey] as? Date else { return nil }

        var fields: [String: SyncValue] = [:]
        for key in record.allKeys() where key != modifiedKey {
            guard let raw = record[key], let value = SyncValue.from(raw) else { continue }
            fields[key] = value
        }

        self.init(id: record.recordID.recordName,
                  type: type,
                  fields: fields,
                  modifiedAt: modified)
    }
}
#endif
