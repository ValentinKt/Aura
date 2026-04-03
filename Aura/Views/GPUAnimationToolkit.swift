import SwiftUI
import Combine

public enum GPUAnimationType {
    case rotation(duration: TimeInterval, clockwise: Bool = true, delay: TimeInterval = 0)
    case rotationTo(from: CGFloat, to: CGFloat, duration: TimeInterval, autoreverses: Bool = true, delay: TimeInterval = 0)
    case scale(from: CGFloat, to: CGFloat, duration: TimeInterval, autoreverses: Bool = true, delay: TimeInterval = 0)
    case scaleX(from: CGFloat, to: CGFloat, duration: TimeInterval, autoreverses: Bool = true, delay: TimeInterval = 0)
    case scaleY(from: CGFloat, to: CGFloat, duration: TimeInterval, autoreverses: Bool = true, delay: TimeInterval = 0)
    case opacity(from: CGFloat, to: CGFloat, duration: TimeInterval, autoreverses: Bool = true, delay: TimeInterval = 0)
    case translationX(from: CGFloat, to: CGFloat, duration: TimeInterval, autoreverses: Bool = true, delay: TimeInterval = 0)
    case translationY(from: CGFloat, to: CGFloat, duration: TimeInterval, autoreverses: Bool = true, delay: TimeInterval = 0)
}

struct NativeGPUAnimationModifier: ViewModifier {
    var animations: [GPUAnimationType]
    var isVisible: Bool

    @State private var isAnimating = false

    // MARK: - Values
    private var rotationAngle: Angle {
        for anim in animations {
            if case let .rotation(_, clockwise, _) = anim {
                return .degrees(isAnimating ? (clockwise ? 360 : -360) : 0)
            }
            if case let .rotationTo(from, to, _, _, _) = anim {
                return .radians(Double(isAnimating ? to : from))
            }
        }
        return .zero
    }

    private var scaleX: CGFloat {
        for anim in animations {
            if case let .scale(from, to, _, _, _) = anim {
                return isAnimating ? to : from
            }
            if case let .scaleX(from, to, _, _, _) = anim {
                return isAnimating ? to : from
            }
        }
        return 1.0
    }

    private var scaleY: CGFloat {
        for anim in animations {
            if case let .scale(from, to, _, _, _) = anim {
                return isAnimating ? to : from
            }
            if case let .scaleY(from, to, _, _, _) = anim {
                return isAnimating ? to : from
            }
        }
        return 1.0
    }

    private var opacityValue: Double {
        for anim in animations {
            if case let .opacity(from, to, _, _, _) = anim {
                return Double(isAnimating ? to : from)
            }
        }
        return 1.0
    }

    private var translationX: CGFloat {
        for anim in animations {
            if case let .translationX(from, to, _, _, _) = anim {
                return isAnimating ? to : from
            }
        }
        return 0
    }

    private var translationY: CGFloat {
        for anim in animations {
            if case let .translationY(from, to, _, _, _) = anim {
                return isAnimating ? to : from
            }
        }
        return 0
    }

    // MARK: - Animations
    private var rotationAnimation: Animation? {
        for anim in animations {
            if case let .rotation(duration, _, delay) = anim {
                return Animation.linear(duration: duration).repeatForever(autoreverses: false).delay(delay)
            }
            if case let .rotationTo(_, _, duration, autoreverses, delay) = anim {
                let base = Animation.easeInOut(duration: duration).delay(delay)
                return autoreverses ? base.repeatForever(autoreverses: true) : base.repeatForever(autoreverses: false)
            }
        }
        return .default
    }

    private var scaleAnimation: Animation? {
        for anim in animations {
            if case let .scale(_, _, duration, autoreverses, delay) = anim {
                let base = Animation.easeInOut(duration: duration).delay(delay)
                return autoreverses ? base.repeatForever(autoreverses: true) : base.repeatForever(autoreverses: false)
            }
            if case let .scaleX(_, _, duration, autoreverses, delay) = anim {
                let base = Animation.easeInOut(duration: duration).delay(delay)
                return autoreverses ? base.repeatForever(autoreverses: true) : base.repeatForever(autoreverses: false)
            }
            if case let .scaleY(_, _, duration, autoreverses, delay) = anim {
                let base = Animation.easeInOut(duration: duration).delay(delay)
                return autoreverses ? base.repeatForever(autoreverses: true) : base.repeatForever(autoreverses: false)
            }
        }
        return .default
    }

    private var opacityAnimation: Animation? {
        for anim in animations {
            if case let .opacity(_, _, duration, autoreverses, delay) = anim {
                let base = Animation.easeInOut(duration: duration).delay(delay)
                return autoreverses ? base.repeatForever(autoreverses: true) : base.repeatForever(autoreverses: false)
            }
        }
        return .default
    }

    private var translationAnimation: Animation? {
        for anim in animations {
            if case let .translationX(_, _, duration, autoreverses, delay) = anim {
                let base = Animation.easeInOut(duration: duration).delay(delay)
                return autoreverses ? base.repeatForever(autoreverses: true) : base.repeatForever(autoreverses: false)
            }
            if case let .translationY(_, _, duration, autoreverses, delay) = anim {
                let base = Animation.easeInOut(duration: duration).delay(delay)
                return autoreverses ? base.repeatForever(autoreverses: true) : base.repeatForever(autoreverses: false)
            }
        }
        return .default
    }

    // MARK: - Flags
    private var hasRotation: Bool { animations.contains { if case .rotation = $0 { return true }; if case .rotationTo = $0 { return true }; return false } }
    private var hasScale: Bool { animations.contains { if case .scale = $0 { return true }; if case .scaleX = $0 { return true }; if case .scaleY = $0 { return true }; return false } }
    private var hasOpacity: Bool { animations.contains { if case .opacity = $0 { return true }; return false } }
    private var hasTranslation: Bool { animations.contains { if case .translationX = $0 { return true }; if case .translationY = $0 { return true }; return false } }

    func body(content: Content) -> some View {
        content
            .modifier(ConditionalRotation(apply: hasRotation, angle: rotationAngle, animation: rotationAnimation, isAnimating: isAnimating))
            .modifier(ConditionalScale(apply: hasScale, scaleX: scaleX, scaleY: scaleY, animation: scaleAnimation, isAnimating: isAnimating))
            .modifier(ConditionalOpacity(apply: hasOpacity, opacityValue: opacityValue, animation: opacityAnimation, isAnimating: isAnimating))
            .modifier(ConditionalTranslation(apply: hasTranslation, x: translationX, y: translationY, animation: translationAnimation, isAnimating: isAnimating))
            .onAppear {
                if isVisible {
                    isAnimating = true
                }
            }
            .onChange(of: isVisible) { _, newValue in
                isAnimating = newValue
            }
    }
}

// MARK: - Conditional Modifiers
struct ConditionalRotation: ViewModifier {
    let apply: Bool
    let angle: Angle
    let animation: Animation?
    let isAnimating: Bool

    func body(content: Content) -> some View {
        if apply {
            content
                .rotationEffect(angle)
                .animation(animation, value: isAnimating)
        } else {
            content
        }
    }
}

struct ConditionalScale: ViewModifier {
    let apply: Bool
    let scaleX: CGFloat
    let scaleY: CGFloat
    let animation: Animation?
    let isAnimating: Bool

    func body(content: Content) -> some View {
        if apply {
            content
                .scaleEffect(x: scaleX, y: scaleY)
                .animation(animation, value: isAnimating)
        } else {
            content
        }
    }
}

struct ConditionalOpacity: ViewModifier {
    let apply: Bool
    let opacityValue: Double
    let animation: Animation?
    let isAnimating: Bool

    func body(content: Content) -> some View {
        if apply {
            content
                .opacity(opacityValue)
                .animation(animation, value: isAnimating)
        } else {
            content
        }
    }
}

struct ConditionalTranslation: ViewModifier {
    let apply: Bool
    let x: CGFloat
    let y: CGFloat
    let animation: Animation?
    let isAnimating: Bool

    func body(content: Content) -> some View {
        if apply {
            content
                .offset(x: x, y: y)
                .animation(animation, value: isAnimating)
        } else {
            content
        }
    }
}

public extension View {
    func gpuAnimation(_ animations: [GPUAnimationType], isVisible: Bool = true) -> some View {
        self.modifier(NativeGPUAnimationModifier(animations: animations, isVisible: isVisible))
    }
}
