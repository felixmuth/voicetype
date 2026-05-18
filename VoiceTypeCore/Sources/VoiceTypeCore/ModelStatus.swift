import Foundation

public enum ModelStatus: Sendable, Equatable {
    case notInstalled
    case installing(progress: Double)   // 0 … 1
    case installed(sizeOnDisk: Int64)
    case failed(reason: String)
}
