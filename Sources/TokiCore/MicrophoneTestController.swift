import Foundation

public final class MicrophoneTestController: ObservableObject, @unchecked Sendable {
    @Published public private(set) var isTesting = false
    @Published public private(set) var inputLevel: Double = 0
    public private(set) var shouldPublishMicrophone = false

    public init() {}

    public func start() {
        isTesting = true
        shouldPublishMicrophone = false
        inputLevel = 0
    }

    public func stop() {
        isTesting = false
        inputLevel = 0
        shouldPublishMicrophone = false
    }

    public func process(inputSamples: [Float]) {
        guard isTesting else {
            return
        }

        inputLevel = Self.level(for: inputSamples)
        shouldPublishMicrophone = false
    }

    public func processSpeakingInput(samples: [Float]) {
        inputLevel = Self.level(for: samples)
        shouldPublishMicrophone = false
    }

    private static func level(for samples: [Float]) -> Double {
        let peak = samples.map { abs(Double($0)) }.max() ?? 0
        return min(1, max(0, peak))
    }
}
