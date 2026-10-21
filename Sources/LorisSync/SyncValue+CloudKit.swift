#if canImport(CloudKit)
import CloudKit
import Foundation

/// Mapping between `SyncValue` and CloudKit field values.
///
/// Kept in its own file so the model stays CloudKit-free and testable: everything
/// above `CloudKitDatabase` deals in `SyncValue`, never `CKRecordValue`.
extension SyncValue {

    /// CloudKit representation. Actual server schema acceptance is a separate gate.
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
    /// Decode the observable native representation, not an inferred schema.
    /// Integral NSNumber encodings become Int exactly, floating encodings stay
    /// Double. Booleans encoded as 0/1 cannot recover their original Swift type;
    /// callers need an explicit schema adapter rather than bool(_:) guessing.
    static func from(_ value: Any) -> SyncValue? {
        switch value {
        case let v as String:   return .string(v)
        case let v as Date:     return .date(v)
        case let v as Data:     return .data(v)
        case let v as [String]: return .stringList(v)
        case let v as [NSNumber]:
            var integers: [Int] = []
            for number in v {
                guard case .int(let integer) = fromNumber(number) else { return nil }
                integers.append(integer)
            }
            return .intList(integers)
        case let v as NSNumber: return fromNumber(v)
        default:
            return nil
        }
    }

    private static func fromNumber(_ number: NSNumber) -> SyncValue? {
        // Decimal -> binary conversion can lose precision; no Decimal case exists.
        guard !(number is NSDecimalNumber) else { return nil }
        switch String(cString: number.objCType) {
        case "c", "s", "i", "l", "q", "B":
            guard let value = Int(exactly: number.int64Value) else { return nil }
            return .int(value)
        case "C", "S", "I", "L", "Q":
            guard let value = Int(exactly: number.uint64Value) else { return nil }
            return .int(value)
        case "f", "d":
            let value = number.doubleValue
            guard value.isFinite else { return nil }
            return .double(value)
        default: return nil
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

    /// All-or-error mapping: never return a partial record that could later erase
    /// omitted fields when saved with allKeys. Rich native fields need an adapter.
    init?(from record: CKRecord, type: String, modifiedKey: String) {
        guard record.recordType.utf8.elementsEqual(type.utf8),
              let modified = record[modifiedKey] as? Date else { return nil }

        var fields: [String: SyncValue] = [:]
        for key in record.allKeys() where key != modifiedKey {
            guard let raw = record[key], let value = SyncValue.from(raw) else { return nil }
            fields[key] = value
        }

        self.init(id: record.recordID.recordName,
                  type: type,
                  fields: fields,
                  modifiedAt: modified)
    }
}
#endif
