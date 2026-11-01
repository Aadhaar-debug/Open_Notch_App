import AppKit
import SwiftUI

/// Music bars animated by Core Animation, which runs in the render server — no
/// SwiftUI re-render or main-thread work per frame while music plays.
struct EqualizerView: NSViewRepresentable {
    var isPlaying: Bool
    var color: NSColor = .white

    func makeNSView(context: Context) -> BarsView { BarsView(color: color) }

    func updateNSView(_ view: BarsView, context: Context) { view.setAnimating(isPlaying) }

    final class BarsView: NSView {
        private var bars: [CALayer] = []
        private var animating = false

        init(color: NSColor) {
            super.init(frame: .zero)
            wantsLayer = true
            for _ in 0..<4 {
                let bar = CALayer()
                bar.backgroundColor = color.cgColor
                bar.cornerRadius = 1
                bar.anchorPoint = CGPoint(x: 0.5, y: 0)
                layer?.addSublayer(bar)
                bars.append(bar)
            }
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let w = bounds.width / CGFloat(bars.count * 2 - 1)
            for (i, bar) in bars.enumerated() {
                bar.bounds = CGRect(x: 0, y: 0, width: w, height: bounds.height)
                bar.position = CGPoint(x: CGFloat(i) * w * 2 + w / 2, y: 0)
                bar.transform = CATransform3DMakeScale(1, 0.3, 1)
            }
            CATransaction.commit()
        }

        func setAnimating(_ on: Bool) {
            guard on != animating else { return }
            animating = on
            let durations: [CFTimeInterval] = [0.45, 0.32, 0.52, 0.38]
            for (i, bar) in bars.enumerated() {
                if on {
                    let a = CABasicAnimation(keyPath: "transform.scale.y")
                    a.fromValue = 0.25
                    a.toValue = 1.0
                    a.duration = durations[i % durations.count]
                    a.autoreverses = true
                    a.repeatCount = .infinity
                    a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    bar.add(a, forKey: "eq")
                } else {
                    bar.removeAnimation(forKey: "eq")
                }
            }
        }
    }
}
