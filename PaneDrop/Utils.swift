import CoreGraphics
import Foundation

enum AppLinks {
    static let privacyPolicy = URL(
        string: "https://davidlabworks.github.io/panedrop-privacy/"
    )!
    static let support = URL(
        string: "https://davidlabworks.github.io/panedrop-privacy/support/"
    )!
}

enum AppLog {
    static func debug(
        _ message: @autoclosure () -> String,
        sourceFile: StaticString = #fileID,
        sourceLine: UInt = #line
    ) {
        #if DEBUG
        let fileName = String(describing: sourceFile)
            .split(separator: "/")
            .last
            .map(String.init) ?? String(describing: sourceFile)
        print("[PaneDrop \(fileName):\(sourceLine)] \(message())")
        #endif
    }
}

enum ScreenFraction {
    private static let tolerance: CGFloat = 0.005
    private static let supportedDenominators = 2...8

    static func label(for value: CGFloat) -> String? {
        guard value > 0, value < 1 else { return nil }

        for denominator in supportedDenominators {
            let numerator = Int((value * CGFloat(denominator)).rounded())
            guard numerator > 0, numerator < denominator else { continue }

            let candidate = CGFloat(numerator) / CGFloat(denominator)
            guard abs(candidate - value) <= tolerance else { continue }

            let divisor = greatestCommonDivisor(numerator, denominator)
            return "\(numerator / divisor)/\(denominator / divisor)"
        }

        return nil
    }

    private static func greatestCommonDivisor(_ first: Int, _ second: Int) -> Int {
        var a = first
        var b = second

        while b != 0 {
            (a, b) = (b, a % b)
        }

        return max(a, 1)
    }
}

extension CGFloat {
    func limited(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(
            Swift.max(self, range.lowerBound),
            range.upperBound
        )
    }
}
