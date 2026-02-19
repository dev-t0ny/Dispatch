import Foundation
import DispatchShared

/// App-internal alias so existing code referencing `DispatchRuntimeEvent` still compiles.
typealias DispatchRuntimeEvent = RuntimeEvent

enum DispatchEventLog {
    static func fileURL() -> URL {
        SharedEventLog.url()
    }

    static func ensureExists() {
        SharedEventLog.ensureDirectory()
    }

    /// Returns the current file size in bytes, or 0 if unreadable.
    static func fileSize() -> UInt64 {
        ensureExists()
        let path = fileURL().path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? UInt64 else {
            return 0
        }
        return size
    }

    /// Reads only the bytes from `offset` to end-of-file and returns the new
    /// lines plus the updated byte offset. If the file was truncated (current
    /// size < offset), resets to 0 and reads everything.
    static func readNewLines(fromByteOffset offset: UInt64) -> (lines: [String], newOffset: UInt64) {
        ensureExists()
        let url = fileURL()

        let currentSize = fileSize()
        let safeOffset = currentSize < offset ? 0 : offset

        guard safeOffset < currentSize else {
            return ([], currentSize)
        }

        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return ([], safeOffset)
        }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: safeOffset)
        } catch {
            return ([], safeOffset)
        }

        let data = handle.readDataToEndOfFile()
        let newOffset = safeOffset + UInt64(data.count)

        guard let text = String(data: data, encoding: .utf8) else {
            return ([], newOffset)
        }

        let lines = text
            .split(whereSeparator: { $0.isNewline })
            .map(String.init)
            .filter { !$0.isEmpty }

        return (lines, newOffset)
    }
}
