import Foundation

/// Stereo audio from `ChimeSynthesizer`.
nonisolated struct RenderedSound: Sendable {
    let sampleRate: Double
    let left: [Float]
    let right: [Float]

    var duration: Double {
        Double(left.count) / sampleRate
    }

    /// A 32-bit float stereo WAV file, which `AVAudioPlayer(data:)` plays without touching disk.
    var wavData: Data {
        let frames = left.count
        let bytesPerFrame = 2 * MemoryLayout<Float>.size
        let dataSize = frames * bytesPerFrame
        var data = Data(capacity: 44 + dataSize)
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(3)) // WAVE_FORMAT_IEEE_FLOAT
        append(UInt16(2))
        append(UInt32(sampleRate))
        append(UInt32(sampleRate) * UInt32(bytesPerFrame))
        append(UInt16(bytesPerFrame))
        append(UInt16(32))
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(dataSize))
        var interleaved = [Float](repeating: 0, count: frames * 2)
        for i in 0..<frames {
            interleaved[2 * i] = left[i]
            interleaved[2 * i + 1] = right[i]
        }
        interleaved.withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }
}
