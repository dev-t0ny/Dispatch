import Foundation

public struct RuntimeEvent: Codable, Sendable {
    public let sessionID: String
    public let agentID: String
    public let tool: String
    public let state: String
    public let reason: String?
    public let timestamp: String

    public init(sessionID: String, agentID: String, tool: String, state: String, reason: String?, timestamp: String) {
        self.sessionID = sessionID
        self.agentID = agentID
        self.tool = tool
        self.state = state
        self.reason = reason
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case agentID = "agent_id"
        case tool
        case state
        case reason
        case timestamp
    }
}
