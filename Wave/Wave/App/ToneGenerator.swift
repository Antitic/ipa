import Foundation
import AVFoundation

/// Générateur de tonalité continue (mode chaud/froid, détecteur de métaux).
final class ToneGenerator: ObservableObject {
    var frequency: Double = 440
    private var amplitude: Double = 0
    private var phase: Double = 0
    private var sampleRate: Double = 44_100
    private var engine: AVAudioEngine?

    func start(amplitude: Double) {
        self.amplitude = amplitude
        guard engine == nil else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true)

        let engine = AVAudioEngine()
        let outFormat = engine.outputNode.inputFormat(forBus: 0)
        sampleRate = outFormat.sampleRate > 0 ? outFormat.sampleRate : 44_100
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }

        let source = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, abl -> OSStatus in
            guard let self else { return noErr }
            let buffers = UnsafeMutableAudioBufferListPointer(abl)
            let step = 2 * Double.pi * self.frequency / self.sampleRate
            for frame in 0..<Int(frameCount) {
                let v = Float(sin(self.phase) * self.amplitude)
                self.phase += step
                if self.phase > 2 * .pi { self.phase -= 2 * .pi }
                for buffer in buffers {
                    let ptr = UnsafeMutableBufferPointer<Float>(buffer)
                    if frame < ptr.count { ptr[frame] = v }
                }
            }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            self.engine = engine
        } catch {
            self.engine = nil
        }
    }

    func setAmplitude(_ a: Double) { amplitude = a }

    func stop() {
        amplitude = 0
        engine?.stop()
        engine = nil
    }

    deinit { engine?.stop() }
}
