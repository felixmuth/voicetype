/// Cleanup-Implementierung für Plan 1: gibt den Text unverändert zurück.
/// Wird in Plan 2 durch FoundationModelCleanup ersetzt.
public struct PassthroughCleanup: TextCleanup {
    public init() {}
    public func cleanup(_ raw: String) async -> String { raw }
}
