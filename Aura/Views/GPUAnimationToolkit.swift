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

public struct GPUAnimationView<Content: View>: NSViewRepresentable {
    public var animations: [GPUAnimationType]
    public var isVisible: Bool
    public var content: Content

    public init(animations: [GPUAnimationType], isVisible: Bool = true, @ViewBuilder content: () -> Content) {
        self.animations = animations
        self.isVisible = isVisible
        self.content = content()
    }

    public func makeNSView(context: Context) -> NSHostingView<Content> {
        let view = NSHostingView(rootView: content)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        applyAnimations(to: view.layer)
        return view
    }

    public func updateNSView(_ nsView: NSHostingView<Content>, context: Context) {
        nsView.rootView = content
        guard let layer = nsView.layer else { return }
        
        if isVisible {
            if layer.animationKeys()?.isEmpty ?? true {
                applyAnimations(to: layer)
            }
        } else {
            layer.removeAllAnimations()
        }
    }

    private func applyAnimations(to layer: CALayer?) {
        guard let layer = layer else { return }
        layer.removeAllAnimations()
        
        let currentTime = layer.convertTime(CACurrentMediaTime(), from: nil)
        
        for (_, anim) in animations.enumerated() {
            let caAnim = CABasicAnimation()
            
            switch anim {
            case .rotation(let duration, let clockwise, let delay):
                caAnim.beginTime = currentTime + delay
                caAnim.keyPath = "transform.rotation.z"
                caAnim.fromValue = 0
                caAnim.toValue = clockwise ? CGFloat.pi * 2 : -CGFloat.pi * 2
                caAnim.duration = duration
                caAnim.repeatCount = .infinity
            case .rotationTo(let from, let to, let duration, let autoreverses, let delay):
                caAnim.beginTime = currentTime + delay
                caAnim.keyPath = "transform.rotation.z"
                caAnim.fromValue = from
                caAnim.toValue = to
                caAnim.duration = duration
                caAnim.autoreverses = autoreverses
                caAnim.repeatCount = .infinity
                caAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            case .scale(let from, let to, let duration, let autoreverses, let delay):
                caAnim.beginTime = currentTime + delay
                caAnim.keyPath = "transform.scale"
                caAnim.fromValue = from
                caAnim.toValue = to
                caAnim.duration = duration
                caAnim.autoreverses = autoreverses
                caAnim.repeatCount = .infinity
                caAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            case .scaleX(let from, let to, let duration, let autoreverses, let delay):
                caAnim.beginTime = currentTime + delay
                caAnim.keyPath = "transform.scale.x"
                caAnim.fromValue = from
                caAnim.toValue = to
                caAnim.duration = duration
                caAnim.autoreverses = autoreverses
                caAnim.repeatCount = .infinity
                caAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            case .scaleY(let from, let to, let duration, let autoreverses, let delay):
                caAnim.beginTime = currentTime + delay
                caAnim.keyPath = "transform.scale.y"
                caAnim.fromValue = from
                caAnim.toValue = to
                caAnim.duration = duration
                caAnim.autoreverses = autoreverses
                caAnim.repeatCount = .infinity
                caAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            case .opacity(let from, let to, let duration, let autoreverses, let delay):
                caAnim.beginTime = currentTime + delay
                caAnim.keyPath = "opacity"
                caAnim.fromValue = from
                caAnim.toValue = to
                caAnim.duration = duration
                caAnim.autoreverses = autoreverses
                caAnim.repeatCount = .infinity
                caAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            case .translationX(let from, let to, let duration, let autoreverses, let delay):
                caAnim.beginTime = currentTime + delay
                caAnim.keyPath = "transform.translation.x"
                caAnim.fromValue = from
                caAnim.toValue = to
                caAnim.duration = duration
                caAnim.autoreverses = autoreverses
                caAnim.repeatCount = .infinity
                caAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            case .translationY(let from, let to, let duration, let autoreverses, let delay):
                caAnim.beginTime = currentTime + delay
                caAnim.keyPath = "transform.translation.y"
                caAnim.fromValue = from
                caAnim.toValue = to
                caAnim.duration = duration
                caAnim.autoreverses = autoreverses
                caAnim.repeatCount = .infinity
                caAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            }
            layer.add(caAnim, forKey: UUID().uuidString)
        }
    }
}

public extension View {
    func gpuAnimation(_ animations: [GPUAnimationType], isVisible: Bool = true) -> some View {
        GPUAnimationView(animations: animations, isVisible: isVisible) {
            self
        }
    }
}
