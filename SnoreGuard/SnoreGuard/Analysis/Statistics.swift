import Foundation

enum Statistics {
    static func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    /// Sample standard deviation (n − 1). Zero for fewer than two values.
    static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let average = mean(values)
        let squares = values.reduce(0) { $0 + ($1 - average) * ($1 - average) }
        return (squares / Double(values.count - 1)).squareRoot()
    }

    /// One-sided permutation test for "treatment is lower than control".
    ///
    /// Returns the share of ways to split the pooled nights into groups of the same sizes whose
    /// difference in means is at least as low as the observed one. Small samples are enumerated
    /// exactly; larger ones use `iterations` seeded random shuffles, so results are repeatable.
    static func oneSidedPermutationPValue(
        treatment: [Double],
        control: [Double],
        exactLimit: Int = 20_000,
        iterations: Int = 10_000,
        seed: UInt64 = 0x5EED
    ) -> Double {
        let pooled = treatment + control
        let n = pooled.count
        let k = treatment.count
        guard k > 0, k < n else { return 1 }
        let total = pooled.reduce(0, +)
        func difference(treatmentSum: Double) -> Double {
            treatmentSum / Double(k) - (total - treatmentSum) / Double(n - k)
        }
        let observed = difference(treatmentSum: treatment.reduce(0, +))
        let tolerance = 1e-9

        if let splits = binomial(n, k, limit: exactLimit) {
            var atLeastAsLow = 0
            forEachCombination(n: n, k: k) { indices in
                let sum = indices.reduce(0) { $0 + pooled[$1] }
                if difference(treatmentSum: sum) <= observed + tolerance {
                    atLeastAsLow += 1
                }
            }
            return Double(atLeastAsLow) / Double(splits)
        }

        var generator = SplitMix64(seed: seed)
        var shuffled = pooled
        var atLeastAsLow = 0
        for _ in 0..<iterations {
            shuffled.shuffle(using: &generator)
            if difference(treatmentSum: shuffled[0..<k].reduce(0, +)) <= observed + tolerance {
                atLeastAsLow += 1
            }
        }
        return Double(atLeastAsLow + 1) / Double(iterations + 1)
    }

    /// n choose k, or `nil` once it exceeds `limit`.
    static func binomial(_ n: Int, _ k: Int, limit: Int) -> Int? {
        let k = min(k, n - k)
        guard k >= 0 else { return 0 }
        var result = 1
        for i in 0..<k {
            result = result * (n - i) / (i + 1)
            if result > limit { return nil }
        }
        return result
    }

    /// Calls `body` with every k-element combination of 0..<n, in lexicographic order.
    static func forEachCombination(n: Int, k: Int, _ body: ([Int]) -> Void) {
        guard k > 0, k <= n else { return }
        var indices = Array(0..<k)
        while true {
            body(indices)
            var i = k - 1
            while i >= 0 && indices[i] == n - k + i {
                i -= 1
            }
            if i < 0 { return }
            indices[i] += 1
            for j in (i + 1)..<k {
                indices[j] = indices[j - 1] + 1
            }
        }
    }
}

/// Small, fast, seedable generator so statistics and demo data are repeatable.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
