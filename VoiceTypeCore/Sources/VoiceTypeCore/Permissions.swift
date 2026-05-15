import AVFoundation
import ApplicationServices

public enum PermissionStatus: Equatable, Sendable {
    case granted, denied, notDetermined
}

/// Liest und (für Mikrofon) erfragt die nötigen Berechtigungen.
public struct Permissions: Sendable {
    public init() {}

    public func microphoneStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:    return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default:    return .denied
        }
    }

    public func requestMicrophone() async -> PermissionStatus {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        return granted ? .granted : .denied
    }

    /// Accessibility kann nicht programmatisch erfragt werden — nur geprüft.
    public func accessibilityStatus() -> PermissionStatus {
        AXIsProcessTrusted() ? .granted : .denied
    }

    public var allGranted: Bool {
        microphoneStatus() == .granted && accessibilityStatus() == .granted
    }
}
