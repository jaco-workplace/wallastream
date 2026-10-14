import AVFoundation
import Foundation

/// Leest uit de ringbuffer, converteert naar 44,1 kHz / 16-bit / stereo (het pipe-formaat van OwnTone)
/// en schrijft dat non-blocking naar de named pipe. Als OwnTone niet leest, wordt audio weggegooid
/// in plaats van opgespaard, zodat de vertraging niet oploopt.
final class PipeWriter: @unchecked Sendable {
    private let ring: RingBuffer
    private let pipePath: String
    private let inputRate: Double
    private var thread: Thread?
    private var running = false

    init(ring: RingBuffer, pipePath: String, inputRate: Double) {
        self.ring = ring
        self.pipePath = pipePath
        self.inputRate = inputRate
    }

    func start() {
        running = true
        let t = Thread { [weak self] in self?.loop() }
        t.name = "Wallastream.PipeWriter"
        t.qualityOfService = .userInteractive
        thread = t
        t.start()
    }

    func stop() {
        running = false
        ring.dataAvailable.signal()
        thread = nil
    }

    private func loop() {
        signal(SIGPIPE, SIG_IGN)

        let chunkFrames = 1024
        let inFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: inputRate,
                                     channels: 2, interleaved: true)!
        let outFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 44_100,
                                      channels: 2, interleaved: true)!
        guard let converter = AVAudioConverter(from: inFormat, to: outFormat),
              let inBuf = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(chunkFrames)),
              let outBuf = AVAudioPCMBuffer(pcmFormat: outFormat,
                                            frameCapacity: AVAudioFrameCount(Double(chunkFrames) * 44_100 / inputRate) + 64)
        else { return }

        var fd: Int32 = -1
        defer { if fd >= 0 { close(fd) } }

        while running {
            _ = ring.dataAvailable.wait(timeout: .now() + .milliseconds(100))
            guard running else { break }

            if fd < 0 {
                // Lukt pas als OwnTone de pipe aan de leeskant open heeft.
                fd = open(pipePath, O_WRONLY | O_NONBLOCK)
                if fd < 0 {
                    while ring.read(into: inBuf.floatChannelData![0], maxFrames: chunkFrames) > 0 {}
                    continue
                }
            }

            while running {
                let n = ring.read(into: inBuf.floatChannelData![0], maxFrames: chunkFrames)
                if n == 0 { break }
                inBuf.frameLength = AVAudioFrameCount(n)

                var fed = false
                outBuf.frameLength = 0
                var error: NSError?
                converter.convert(to: outBuf, error: &error) { _, status in
                    if fed { status.pointee = .noDataNow; return nil }
                    fed = true
                    status.pointee = .haveData
                    return inBuf
                }
                if error != nil { continue }

                let bytes = Int(outBuf.frameLength) * 4
                guard bytes > 0 else { continue }
                let written = write(fd, outBuf.int16ChannelData![0], bytes)
                if written < 0 && errno != EAGAIN {
                    // EPIPE e.d.: OwnTone heeft de pipe gesloten, later opnieuw openen.
                    close(fd)
                    fd = -1
                    break
                }
            }
        }
    }
}
