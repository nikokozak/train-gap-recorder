import Testing
@testable import TrainGapRecorder

/// The motion chart shows the measure the stop detector uses (joltMilliG in internal/recording/stops.go).
struct MotionJoltTests {
    private func batch(x: [Int], y: [Int], z: [Int]) -> RecorderMotion {
        RecorderMotion(tMS: 0, hz: 20, xMilliG: x, yMilliG: y, zMilliG: z, gravityMilliG: [0, 0, -1000])
    }

    @Test func joltIsTheRMSChangeBetweenReadings() {
        // Changes: (3, 4, 0) then (-3, -4, 0), each 5 mg long.
        #expect(batch(x: [0, 3, 0], y: [0, 4, 0], z: [0, 0, 0]).joltMilliG == 5)
    }

    @Test func steadyAccelerationIsNotJolt() {
        #expect(batch(x: [80, 80, 80], y: [0, 0, 0], z: [0, 0, 0]).joltMilliG == 0)
    }

    @Test func oneReadingHasNoJolt() {
        #expect(batch(x: [10], y: [10], z: [10]).joltMilliG == nil)
    }
}
