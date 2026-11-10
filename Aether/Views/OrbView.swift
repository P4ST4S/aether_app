import SwiftUI

struct OrbView: View {
    enum Phase: String { case idle, processing, generating, listening, error }
    let phase: Phase
    var animate = true
    var audioLevel: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TimelineView(.animation(minimumInterval: phase == .idle ? 1.0 / 12 : 1.0 / 24,
                                paused: !animate || reduceMotion)) { timeline in
            let time = animate && !reduceMotion ? timeline.date.timeIntervalSinceReferenceDate : 0
            let speed = phase == .processing || phase == .generating ? 1.5 : 0.35
            let angle = time * speed
            let breath = reduceMotion || !animate ? 1 : 0.96 + 0.04 * sin(time * 1.3)
            GeometryReader { geometry in
                let side = min(geometry.size.width, geometry.size.height)
                ZStack {
                    Circle().fill(.blue.opacity(scheme == .dark ? 0.14 : 0.08))
                        .blur(radius: reduceTransparency ? 0 : side * 0.14)
                    Circle().fill(scheme == .dark ? Color(red: 0.04, green: 0.05, blue: 0.16) : Color(red: 0.87, green: 0.94, blue: 1))
                    ZStack {
                        Ellipse().fill(.cyan).frame(width: side * 0.72, height: side * 0.52)
                            .offset(x: side * 0.15 * sin(angle), y: -side * 0.23)
                        Ellipse().fill(phase == .error ? .orange : .indigo)
                            .frame(width: side * 0.9, height: side * 0.5).rotationEffect(.degrees(45))
                            .offset(x: side * 0.2 * cos(angle), y: side * 0.24)
                        Ellipse().fill(.purple.opacity(0.9)).frame(width: side * 0.5, height: side * 0.8)
                            .offset(x: -side * 0.24, y: side * 0.1 * sin(angle))
                        Ellipse().fill(.white.opacity(0.9)).frame(width: side * 0.45, height: side * 0.17)
                            .rotationEffect(.degrees(-35)).offset(x: side * 0.12, y: -side * 0.18)
                    }
                    .blur(radius: side * 0.13)
                    .rotationEffect(.radians(angle * 0.45))
                    .clipShape(.circle)
                    Circle().strokeBorder(.white.opacity(0.5), lineWidth: 0.8)
                    Circle().strokeBorder(AngularGradient(colors: [.clear, .cyan.opacity(0.8), .white, .purple, .clear], center: .center), lineWidth: side * 0.025)
                        .rotationEffect(.radians(-angle))
                }
                .scaleEffect(breath + (phase == .listening ? audioLevel * 0.12 : 0))
                .frame(width: side, height: side)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityLabel("Aether, \(phase.rawValue)")
    }
}

struct FloatingSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(.background, in: .rect(cornerRadius: 28))
        } else {
            content.glassEffect(.regular, in: .rect(cornerRadius: 28))
        }
    }
}
