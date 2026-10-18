import Foundation

/// Model Context Protocol (MCP) and JSON-RPC 2.0 constants and types
public enum MCPProtocol {
    public static let protocolVersion = "2024-11-05"
    public static let serverName = "tail-userspace"
    public static let serverVersion = "1.0.0"

    // Standard JSON-RPC 2.0 Error Codes
    public static let parseError = -32700
    public static let invalidRequest = -32600
    public static let methodNotFound = -32601
    public static let invalidParams = -32602
    public static let internalError = -32603

    /// Builds a valid JSON-RPC 2.0 response dictionary
    public static func makeResponse(id: Any, result: Any) -> [String: Any] {
        return [
            "jsonrpc": "2.0",
            "id": id,
            "result": result
        ]
    }

    /// Builds a valid JSON-RPC 2.0 error dictionary
    public static func makeError(id: Any?, code: Int, message: String, data: Any? = nil) -> [String: Any] {
        var errObj: [String: Any] = [
            "code": code,
            "message": message
        ]
        if let data = data {
            errObj["data"] = data
        }
        var res: [String: Any] = [
            "jsonrpc": "2.0",
            "error": errObj
        ]
        if let id = id {
            res["id"] = id
        } else {
            res["id"] = NSNull()
        }
        return res
    }
}

/// Representation of an MCP Tool specification
public struct MCPTool {
    public let name: String
    public let description: String
    public let inputSchema: [String: Any]

    public init(name: String, description: String, inputSchema: [String: Any]) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }

    public func asDictionary() -> [String: Any] {
        return [
            "name": name,
            "description": description,
            "inputSchema": inputSchema
        ]
    }
}

/// Representation of an MCP Resource specification
public struct MCPResource {
    public let uri: String
    public let name: String
    public let description: String?
    public let mimeType: String?

    public init(uri: String, name: String, description: String? = nil, mimeType: String? = "application/json") {
        self.uri = uri
        self.name = name
        self.description = description
        self.mimeType = mimeType
    }

    public func asDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "uri": uri,
            "name": name
        ]
        if let desc = description {
            dict["description"] = desc
        }
        if let mime = mimeType {
            dict["mimeType"] = mime
        }
        return dict
    }
}

/// Representation of an MCP Prompt specification
public struct MCPPrompt {
    public let name: String
    public let description: String?
    public let arguments: [[String: Any]]?

    public init(name: String, description: String? = nil, arguments: [[String: Any]]? = nil) {
        self.name = name
        self.description = description
        self.arguments = arguments
    }

    public func asDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "name": name
        ]
        if let desc = description {
            dict["description"] = desc
        }
        if let args = arguments {
            dict["arguments"] = args
        }
        return dict
    }
}
