import Foundation

public struct ModelDescriptor: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable { case whisperKit, mlx }

    public let kind: Kind
    public let id: String              // z. B. "openai_whisper-large-v3-turbo"
    public let displayName: String     // "Whisper large-v3-turbo"
    public let approxSizeBytes: Int64
    public let isDefault: Bool

    public init(
        kind: Kind, id: String, displayName: String,
        approxSizeBytes: Int64, isDefault: Bool
    ) {
        self.kind = kind
        self.id = id
        self.displayName = displayName
        self.approxSizeBytes = approxSizeBytes
        self.isDefault = isDefault
    }
}
