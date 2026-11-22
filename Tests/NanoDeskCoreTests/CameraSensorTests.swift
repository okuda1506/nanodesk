import CameraSensor
import Testing

struct CameraSensorTests {
    private let width = Int(ND_CAMERA_WIDTH)
    private let height = Int(ND_CAMERA_HEIGHT)

    private func grade(_ bytes: inout [UInt8], stride: Int, seed: UInt32) {
        bytes.withUnsafeMutableBufferPointer { NDGradeCameraFrame($0.baseAddress, stride, seed) }
    }

    @Test func grainChangesBetweenFramesAndIsStrongerInShadows() {
        let stride = width * 4 + 12
        var scene = [UInt8](repeating: 36, count: height / 2 * stride)
        scene += [UInt8](repeating: 220, count: height / 2 * stride)
        var first = scene, next = scene
        grade(&first, stride: stride, seed: 1)
        grade(&next, stride: stride, seed: 2)

        func temporalDifference(row: Int) -> Int {
            let indices = (0..<width).map { row * stride + $0 * 4 }
            return indices.reduce(0) { $0 + abs(Int(first[$1]) - Int(next[$1])) }
        }
        let shadow = temporalDifference(row: 2)
        let light = temporalDifference(row: height - 2)
        #expect(light > 0 && shadow > 3 * light)
        for y in [0, height - 1] {
            let offset = y * stride + width * 4
            #expect(first[offset..<offset + 12] == scene[offset..<offset + 12])
            #expect(first[y * stride + 3] == scene[y * stride + 3])
        }
    }

    @Test func fineColorBoundariesSoftenWithoutEliminatingLuminanceDetail() {
        let stride = width * 4
        var frame = [UInt8](repeating: 128, count: height * stride)
        // Red and green with nearly equal luma, next to a high-contrast neutral pair.
        for row in [0, stride] {
            frame.replaceSubrange(row..<row + 16, with: [
                0, 0, 255, 255, 0, 131, 0, 255, 0, 0, 0, 255, 255, 255, 255, 255
            ])
        }
        grade(&frame, stride: stride, seed: 5)
        #expect(abs(Int(frame[2]) - Int(frame[6])) < 100)
        let contrast = Int(frame[12]) - Int(frame[8])
        #expect(contrast > 100 && contrast < 225)
    }
}
