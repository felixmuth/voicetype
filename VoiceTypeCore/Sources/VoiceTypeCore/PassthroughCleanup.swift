/// Cleanup-Implementierung, die den Text unverändert zurückgibt. Wird vom
/// AppController als Fallback verwendet, wenn `settings.cleanupEnabled`
/// auf `false` steht (z.B. wenn der Nutzer das Aufpolieren bewusst
/// abschaltet). Bleibt parallel zu `FoundationModelCleanup` bestehen.
public struct PassthroughCleanup: TextCleanup {
    public init() {}
    public func cleanup(_ raw: String) async -> String { raw }
}
