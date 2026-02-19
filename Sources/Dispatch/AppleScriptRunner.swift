import Foundation

protocol TerminalControlling {
    var app: TerminalApp { get }
    func launchWindow(command: String) throws -> Int
    func setBounds(windowID: Int, bounds: WindowBounds) throws
    func closeWindow(windowID: Int) throws
    func focusWindow(windowID: Int) throws
    func listWindowSnapshots() throws -> [TerminalWindowSnapshot]
    func applyIdentity(windowID: Int, title: String, badge: String, tone: AgentTone) throws
    /// Read the last N lines of visible text from the terminal session in the given window.
    func readSessionContent(windowID: Int, lineCount: Int) throws -> String
    /// Check which window IDs have sessions that appear idle / waiting for input.
    /// Returns the set of window IDs where the session is at a shell prompt or idle.
    func detectIdleWindowIDs(among windowIDs: [Int]) throws -> Set<Int>
}

struct AppleScriptRunner {
    func run(_ script: String) throws -> NSAppleEventDescriptor? {
        guard let appleScript = NSAppleScript(source: script) else {
            throw DispatchError.appleScript("Invalid AppleScript source.")
        }

        var errorDict: NSDictionary?
        let result = appleScript.executeAndReturnError(&errorDict)
        if let errorDict {
            throw DispatchError.appleScript(errorDict.description)
        }

        if result.descriptorType == typeNull {
            return nil
        }
        return result
    }

    func intValue(from descriptor: NSAppleEventDescriptor?) throws -> Int {
        guard let descriptor else {
            throw DispatchError.system("Terminal did not return a window ID.")
        }

        if descriptor.descriptorType == typeSInt32 {
            return Int(descriptor.int32Value)
        }

        if let text = descriptor.stringValue, let value = Int(text) {
            return value
        }

        throw DispatchError.system("Unable to parse terminal window ID.")
    }

    func intArrayValue(from descriptor: NSAppleEventDescriptor?) throws -> [Int] {
        guard let descriptor else {
            return []
        }

        if descriptor.descriptorType == typeAEList {
            var values: [Int] = []
            let count = descriptor.numberOfItems
            if count > 0 {
                for index in 1...count {
                    let item = descriptor.atIndex(index)
                    if let item {
                        if item.descriptorType == typeSInt32 {
                            values.append(Int(item.int32Value))
                        } else if let text = item.stringValue, let value = Int(text) {
                            values.append(value)
                        }
                    }
                }
            }
            return values
        }

        if descriptor.descriptorType == typeSInt32 {
            return [Int(descriptor.int32Value)]
        }

        if let text = descriptor.stringValue, let value = Int(text) {
            return [value]
        }

        return []
    }

    func stringArrayValue(from descriptor: NSAppleEventDescriptor?) -> [String] {
        guard let descriptor else {
            return []
        }

        if descriptor.descriptorType == typeAEList {
            var values: [String] = []
            let count = descriptor.numberOfItems
            if count > 0 {
                for index in 1...count {
                    if let item = descriptor.atIndex(index), let text = item.stringValue {
                        values.append(text)
                    }
                }
            }
            return values
        }

        if let text = descriptor.stringValue {
            return [text]
        }

        return []
    }

    func windowSnapshotsValue(from descriptor: NSAppleEventDescriptor?) -> [TerminalWindowSnapshot] {
        guard let descriptor else {
            return []
        }

        guard descriptor.descriptorType == typeAEList else {
            return []
        }

        var snapshots: [TerminalWindowSnapshot] = []
        let count = descriptor.numberOfItems
        guard count > 0 else { return [] }

        for index in 1...count {
            guard let row = descriptor.atIndex(index), row.descriptorType == typeAEList else { continue }
            let values = (try? intArrayValue(from: row)) ?? []
            guard values.count >= 5 else { continue }

            let snapshot = TerminalWindowSnapshot(
                windowID: values[0],
                left: values[1],
                top: values[2],
                right: values[3],
                bottom: values[4]
            )
            snapshots.append(snapshot)
        }

        return snapshots
    }
}
