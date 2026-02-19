import Foundation

protocol TerminalControlling {
    var app: TerminalApp { get }
    func launchWindow(command: String) throws -> Int
    func setBounds(windowID: Int, bounds: WindowBounds) throws
    func closeWindow(windowID: Int) throws
    func focusWindow(windowID: Int) throws
    func listWindowIDs() throws -> [Int]
    func applyIdentity(windowID: Int, title: String, badge: String, tone: AgentTone) throws
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
}
