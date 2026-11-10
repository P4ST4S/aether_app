import AppKit
import Observation
import SwiftData
import SwiftUI

@MainActor @Observable
final class AppRuntime {
    static let shared = AppRuntime()
    let settings = AppSettings()
    var store: ConversationStore?
    var storageIssue: String?
    var panelVisible = false
    var shortcutIssue: String?
    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var panel: AssistantPanel?
    @ObservationIgnored private var previousApplication: NSRunningApplication?
    @ObservationIgnored private let shortcut = GlobalShortcut()

    private init() { initializeStorage() }

    func initializeStorage() {
        do {
            let configuration: ModelConfiguration
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            } else {
                let directory = URL.applicationSupportDirectory.appending(path: "Aether", directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                configuration = ModelConfiguration("AetherHistory", url: directory.appending(path: "History.store"), cloudKitDatabase: .none)
            }
            let container = try ModelContainer(for: Conversation.self, StoredMessage.self, configurations: configuration)
            self.container = container
            store = try ConversationStore(context: container.mainContext, settings: settings)
            storageIssue = nil
        } catch {
            storageIssue = "Aether could not open its local history. Your existing files have been left in place. \(error.localizedDescription)"
        }
    }

    func start() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        applyShortcut()
        Task { await store?.checkConnection() }
    }

    func applyShortcut() {
        shortcutIssue = shortcut.register(modifiers: settings.shortcutModifiers, key: settings.shortcutKey) { [weak self] in
            self?.togglePanel()
        }
    }

    func togglePanel() { panelVisible ? hidePanel() : showPanel() }

    func showPanel() {
        if panel == nil {
            let panel = AssistantPanel(contentRect: NSRect(x: 0, y: 0, width: 660, height: 460),
                                       styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "Aether"
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            // Liquid Glass supplies its own edge; a second WindowServer shadow creates an outer outline.
            panel.hasShadow = false
            panel.isMovableByWindowBackground = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
            let hostingView = NSHostingView(rootView: AssistantRootView(runtime: self))
            hostingView.focusRingType = .none
            panel.contentView = hostingView
            panel.onDismiss = { [weak self] in self?.hidePanel() }
            self.panel = panel
        }
        if !panelVisible, NSWorkspace.shared.frontmostApplication?.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApplication = NSWorkspace.shared.frontmostApplication
        }
        panelVisible = true
        resizePanel(expanded: store?.isExpanded ?? false, animated: false)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            if let panel {
                panel.setFrameOrigin(NSPoint(x: visible.midX - panel.frame.width / 2, y: visible.maxY - panel.frame.height - 80))
            }
        }
        NSApp.activate()
        panel?.makeKeyAndOrderFront(nil)
        store?.focusRequest = UUID()
    }

    func hidePanel(restoreFocus: Bool = true) {
        panel?.orderOut(nil)
        panelVisible = false
        SpeechService.shared.stopAll()
        if restoreFocus { previousApplication?.activate(); previousApplication = nil }
    }

    func resizePanel(expanded: Bool, animated: Bool = true) {
        guard let panel else { return }
        let available = (panel.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 900)
        let size = NSSize(width: min(expanded ? 760 : 660, available.width - 32),
                          height: min(expanded ? 740 : 470, available.height - 48))
        var frame = panel.frame
        frame.origin.x += (frame.width - size.width) / 2
        frame.origin.y += frame.height - size.height
        frame.size = size
        frame.origin.y = max(available.minY + 16, min(frame.origin.y, available.maxY - size.height))
        frame.origin.x = max(available.minX + 16, min(frame.origin.x, available.maxX - size.width))
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                panel.animator().setFrame(frame, display: true)
            }
        } else { panel.setFrame(frame, display: true) }
    }

    func shutdown() {
        store?.stop()
        SpeechService.shared.stopAll()
    }
}

final class AssistantPanel: NSPanel {
    var onDismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onDismiss?() }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { AppRuntime.shared.start() }
    func applicationWillTerminate(_ notification: Notification) { AppRuntime.shared.shutdown() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppRuntime.shared.showPanel()
        return false
    }
}
