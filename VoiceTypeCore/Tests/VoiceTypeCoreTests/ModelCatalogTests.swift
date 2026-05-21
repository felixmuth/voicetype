import Testing
@testable import VoiceTypeCore

@Suite struct ModelCatalogTests {

    @Test func whisperKitDefaultIsLargeV3() {
        let def = ModelCatalog.whisperKitDefault
        #expect(def.kind == .whisperKit)
        #expect(def.id == "openai_whisper-large-v3")
        #expect(def.isDefault)
    }

    @Test func mlxDefaultIsQwen25ThreeB() {
        let def = ModelCatalog.mlxDefault
        #expect(def.kind == .mlx)
        #expect(def.id == "mlx-community/Qwen2.5-3B-Instruct-4bit")
        #expect(def.isDefault)
    }

    @Test func whisperKitCatalogContainsKnownIds() {
        let ids = ModelCatalog.whisperKitAll.map(\.id)
        #expect(ids.contains("openai_whisper-large-v3-turbo"))
        #expect(ids.contains("openai_whisper-large-v3"))
    }

    @Test func mlxCatalogContainsKnownIds() {
        // Katalog ist derzeit bewusst auf Qwen 2.5 3B reduziert — 7B und
        // Llama 3.2 sind raus, Gemma 3 wegen lm_head-Mismatch deaktiviert.
        let ids = ModelCatalog.mlxAll.map(\.id)
        #expect(ids.contains("mlx-community/Qwen2.5-3B-Instruct-4bit"))
    }

    @Test func lookupReturnsNilForUnknownId() {
        #expect(ModelCatalog.whisperKit(id: "does-not-exist") == nil)
        #expect(ModelCatalog.mlx(id: "does-not-exist") == nil)
    }

    @Test func lookupReturnsDescriptorForKnownId() {
        let d = ModelCatalog.whisperKit(id: "openai_whisper-large-v3-turbo")
        #expect(d?.displayName == "Whisper large-v3-turbo")
    }
}
