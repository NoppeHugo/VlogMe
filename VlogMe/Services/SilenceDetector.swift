import AVFoundation

/// Détecte les plages silencieuses dans un fichier audio et retourne les plages non-silencieuses.
struct SilenceDetector {

    private static let thresholdLinear: Float = pow(10.0, -35.0 / 20.0)  // -35 dB
    private static let minSilenceSecs: Double = 0.25

    /// Retourne les sous-plages non-silencieuses du fichier. Si l'analyse échoue, retourne [] (signifie "tout garder").
    static func nonSilentRanges(in url: URL) async -> [CMTimeRange] {
        let asset = AVURLAsset(url: url)
        guard
            let duration = try? await asset.load(.duration),
            let track = try? await asset.loadTracks(withMediaType: .audio).first
        else { return [] }

        let fullRange = CMTimeRange(start: .zero, duration: duration)
        let silent = readSilentRanges(track: track, asset: asset, totalDuration: duration)
        let nonSilent = complement(of: silent, in: fullRange)
        return nonSilent.isEmpty ? [fullRange] : nonSilent
    }

    private static func readSilentRanges(
        track: AVAssetTrack,
        asset: AVAsset,
        totalDuration: CMTime
    ) -> [CMTimeRange] {
        guard let reader = try? AVAssetReader(asset: asset) else { return [] }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 44100.0
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        guard reader.canAdd(output) else { return [] }
        reader.add(output)
        guard reader.startReading() else { return [] }

        var result: [CMTimeRange] = []
        var silenceStart: CMTime? = nil
        var cursor: CMTime = .zero
        let sampleRate: Double = 44100

        while let buffer = output.copyNextSampleBuffer() {
            let count = CMSampleBufferGetNumSamples(buffer)
            guard count > 0, let block = CMSampleBufferGetDataBuffer(buffer) else { continue }

            let byteLen = CMBlockBufferGetDataLength(block)
            var raw = [UInt8](repeating: 0, count: byteLen)
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: byteLen, destination: &raw)

            let sampleCount = byteLen / 2
            var sumSq: Float = 0
            raw.withUnsafeBytes { ptr in
                let s16 = ptr.bindMemory(to: Int16.self)
                for i in 0..<s16.count { let s = Float(s16[i]) / 32768.0; sumSq += s * s }
            }
            let rms = sampleCount > 0 ? sqrtf(sumSq / Float(sampleCount)) : 0
            let dur = CMTime(value: CMTimeValue(count), timescale: CMTimeScale(sampleRate))

            if rms < thresholdLinear {
                if silenceStart == nil { silenceStart = cursor }
            } else if let start = silenceStart {
                let d = cursor - start
                if d.seconds > minSilenceSecs { result.append(CMTimeRange(start: start, duration: d)) }
                silenceStart = nil
            }
            cursor = cursor + dur
        }

        if let start = silenceStart {
            let d = totalDuration - start
            if d.seconds > minSilenceSecs { result.append(CMTimeRange(start: start, duration: d)) }
        }
        return result
    }

    private static func complement(of silent: [CMTimeRange], in total: CMTimeRange) -> [CMTimeRange] {
        var result: [CMTimeRange] = []
        var cursor = total.start
        let sorted = silent.sorted { CMTimeCompare($0.start, $1.start) < 0 }

        for s in sorted {
            if CMTimeCompare(s.end, cursor) <= 0 { continue }
            let rangeStart = CMTimeMaximum(s.start, cursor)
            if CMTimeCompare(rangeStart, cursor) > 0 {
                result.append(CMTimeRange(start: cursor, end: rangeStart))
            }
            cursor = s.end
            if CMTimeCompare(cursor, total.end) >= 0 { break }
        }
        if CMTimeCompare(cursor, total.end) < 0 {
            result.append(CMTimeRange(start: cursor, end: total.end))
        }
        return result.filter { $0.duration.seconds > 0.05 }
    }
}
