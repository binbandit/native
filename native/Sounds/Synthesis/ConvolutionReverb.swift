import Accelerate
import Foundation

/// A light stereo room for `ChimeSynthesizer`. The impulse responses are seeded noise with an
/// exponential decay that darkens as it falls, applied by FFT convolution. Noise reverbs stay smooth
/// on nearly pure tones, where comb-filter reverbs (Freeverb and kin) ring at their own pitches.
nonisolated struct ConvolutionReverb: Sendable {
    let room: ChimeSynthesizer.Room
    let sampleRate: Double

    func apply(left: inout [Float], right: inout [Float]) {
        var noise = SeededNoise(seed: 0x6E61_7469_7665)
        let leftResponse = impulseResponse(noise: &noise)
        let rightResponse = impulseResponse(noise: &noise)
        // The room hears the mono sum; two decorrelated responses give the width.
        let dry = vDSP.multiply(0.5, vDSP.add(left, right))
        let wet = Float(ChimeSynthesizer.amplitude(decibels: room.wet))
        left = vDSP.add(left, vDSP.multiply(wet, convolve(dry, leftResponse)))
        right = vDSP.add(right, vDSP.multiply(wet, convolve(dry, rightResponse)))
    }

    private func impulseResponse(noise: inout SeededNoise) -> [Float] {
        let predelay = Int(room.predelay * sampleRate)
        let tail = Int(room.t60 * sampleRate)
        var response = [Float](repeating: 0, count: predelay + tail)
        let decay = -6.907_755 / (room.t60 * sampleRate)
        // A diffuse room builds up over a few milliseconds rather than starting at full level.
        let onset = 0.008 * sampleRate
        var state: Float = 0
        for i in 0..<tail {
            let t = Double(i)
            let corner = room.brightness * (1 - 0.75 * t / Double(tail))
            let coefficient = Float(exp(-2 * Double.pi * corner / sampleRate))
            state = coefficient * state + (1 - coefficient) * noise.nextSignal()
            response[predelay + i] = state * Float(exp(decay * t) * min(t / onset, 1))
        }
        // Unit energy, so `room.wet` alone sets the reverb's level.
        let energy = vDSP.sumOfSquares(response).squareRoot()
        return vDSP.multiply(1 / max(energy, .leastNonzeroMagnitude), response)
    }

    /// Linear convolution, truncated to `signal`'s length (the tail past it is trimmed anyway).
    private func convolve(_ signal: [Float], _ kernel: [Float]) -> [Float] {
        let log2n = vDSP_Length(log2(Double(signal.count + kernel.count)).rounded(.up))
        let size = 1 << Int(log2n)
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return [Float](repeating: 0, count: signal.count)
        }
        defer { vDSP_destroy_fftsetup(setup) }

        func transform(_ real: inout [Float], _ imaginary: inout [Float], _ direction: FFTDirection) {
            real.withUnsafeMutableBufferPointer { realPointer in
                imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                    guard let realBase = realPointer.baseAddress, let imaginaryBase = imaginaryPointer.baseAddress
                    else { return }
                    var split = DSPSplitComplex(realp: realBase, imagp: imaginaryBase)
                    vDSP_fft_zip(setup, &split, 1, log2n, direction)
                }
            }
        }

        var signalReal = signal + [Float](repeating: 0, count: size - signal.count)
        var signalImaginary = [Float](repeating: 0, count: size)
        var kernelReal = kernel + [Float](repeating: 0, count: size - kernel.count)
        var kernelImaginary = [Float](repeating: 0, count: size)
        transform(&signalReal, &signalImaginary, FFTDirection(FFT_FORWARD))
        transform(&kernelReal, &kernelImaginary, FFTDirection(FFT_FORWARD))
        var real = vDSP.subtract(vDSP.multiply(signalReal, kernelReal), vDSP.multiply(signalImaginary, kernelImaginary))
        var imaginary = vDSP.add(vDSP.multiply(signalReal, kernelImaginary), vDSP.multiply(signalImaginary, kernelReal))
        transform(&real, &imaginary, FFTDirection(FFT_INVERSE))
        return vDSP.multiply(1 / Float(size), Array(real.prefix(signal.count)))
    }
}
