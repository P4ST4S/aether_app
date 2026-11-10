import Foundation
import Observation
import SwiftUI

@MainActor @Observable
final class AppSettings {
    private let defaults: UserDefaults
    var endpoint: String { didSet { defaults.set(endpoint, forKey: "endpoint") } }
    var model: String { didSet { defaults.set(model, forKey: "model") } }
    var contextLength: Int { didSet { defaults.set(contextLength, forKey: "contextLength") } }
    var temperature: Double { didSet { defaults.set(temperature, forKey: "temperature") } }
    var responseLimit: Int { didSet { defaults.set(responseLimit, forKey: "responseLimit") } }
    var enableThinking: Bool { didSet { defaults.set(enableThinking, forKey: "enableThinking") } }
    var systemPrompt: String { didSet { defaults.set(systemPrompt, forKey: "systemPrompt") } }
    var appearance: String { didSet { defaults.set(appearance, forKey: "appearance") } }
    var animateOrb: Bool { didSet { defaults.set(animateOrb, forKey: "animateOrb") } }
    var shortcutModifiers: String { didSet { defaults.set(shortcutModifiers, forKey: "shortcutModifiers") } }
    var shortcutKey: String { didSet { defaults.set(shortcutKey, forKey: "shortcutKey") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        endpoint = defaults.string(forKey: "endpoint") ?? "http://127.0.0.1:11434"
        model = defaults.string(forKey: "model") ?? "huihui_ai/qwen3.5-abliterated:9b-q4_K"
        contextLength = defaults.object(forKey: "contextLength") as? Int ?? 8192
        temperature = defaults.object(forKey: "temperature") as? Double ?? 0.6
        responseLimit = defaults.object(forKey: "responseLimit") as? Int ?? 2048
        enableThinking = defaults.object(forKey: "enableThinking") as? Bool ?? false
        systemPrompt = defaults.string(forKey: "systemPrompt") ?? "You are Aether, a helpful, thoughtful assistant running locally on the user's Mac. Be clear, accurate, and concise. Reply in the user's language."
        appearance = defaults.string(forKey: "appearance") ?? "system"
        animateOrb = defaults.object(forKey: "animateOrb") as? Bool ?? true
        shortcutModifiers = defaults.string(forKey: "shortcutModifiers") ?? "option"
        shortcutKey = defaults.string(forKey: "shortcutKey") ?? "space"
    }

    var colorScheme: ColorScheme? {
        switch appearance { case "light": .light; case "dark": .dark; default: nil }
    }

    var options: GenerationOptions {
        GenerationOptions(num_ctx: min(max(contextLength, 2048), 65536),
                          temperature: min(max(temperature, 0), 2),
                          num_predict: min(max(responseLimit, 128), max(128, contextLength / 2)))
    }
}
