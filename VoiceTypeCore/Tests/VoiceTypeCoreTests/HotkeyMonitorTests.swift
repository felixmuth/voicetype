import Testing
import AppKit
@testable import VoiceTypeCore

@MainActor
@Suite struct HotkeyMonitorTests {

    @Test func resolveModifierFn() {
        let result = HotkeyMonitor.hotkeyName(
            keyCode: 0, modifierFlags: [.function], isKeyDown: false)
        #expect(result == "fn")
    }

    @Test func resolveModifierCmd() {
        let result = HotkeyMonitor.hotkeyName(
            keyCode: 0, modifierFlags: [.command], isKeyDown: false)
        #expect(result == "cmd")
    }

    @Test func resolveModifierOpt() {
        let result = HotkeyMonitor.hotkeyName(
            keyCode: 0, modifierFlags: [.option], isKeyDown: false)
        #expect(result == "opt")
    }

    @Test func resolveFunctionKeyF13() {
        let result = HotkeyMonitor.hotkeyName(
            keyCode: 105, modifierFlags: [], isKeyDown: true)
        #expect(result == "f13")
    }

    @Test func resolveFunctionKeyF1() {
        let result = HotkeyMonitor.hotkeyName(
            keyCode: 122, modifierFlags: [], isKeyDown: true)
        #expect(result == "f1")
    }

    @Test func resolveUnknownReturnsNil() {
        // KeyCode 50 (`§`) ist nicht in den Function-Keys; ohne Modifier
        // gibt's nichts Passendes.
        let result = HotkeyMonitor.hotkeyName(
            keyCode: 50, modifierFlags: [], isKeyDown: true)
        #expect(result == nil)
    }

    @Test func functionKeyOnKeyUpReturnsNil() {
        // Capture darf nur auf keyDown auslösen — nicht auf keyUp.
        let result = HotkeyMonitor.hotkeyName(
            keyCode: 105, modifierFlags: [], isKeyDown: false)
        #expect(result == nil)
    }
}
