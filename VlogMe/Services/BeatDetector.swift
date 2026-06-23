import AVFoundation
import Accelerate

/// Estimation du tempo d'un morceau, sans dépendance externe.
///
/// Principe : on lit l'audio en PCM mono ré-échantillonné, on calcule une
/// enveloppe d'énergie (≈ « onset strength »), puis une autocorrélation pour
/// trouver la période de battement la plus probable (70–180 BPM). Assez bon
/// pour caler un montage « hook » sur le beat — pas un analyseur de studio.
enum BeatDetector {

    /// Tempo estimé en BPM, ou `nil` si indétectable.
    static func estimateBPM(url: URL) async -> Double? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else { return nil }

        let sampleRate: Double = 22050
        let hop = 512
        let maxSeconds = 30.0

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: sampleRate
        ]

        guard let reader = try? AVAssetReader(asset: asset) else { return nil }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }

        var envelope: [Float] = []
        var carry: [Float] = []
        var remaining = Int(sampleRate * maxSeconds)

        while remaining > 0, let sb = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sb) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            guard length > 0 else { continue }
            var chunk = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: &chunk)
            remaining -= chunk.count
            carry.append(contentsOf: chunk)
            while carry.count >= hop {
                var energy: Float = 0
                carry.withUnsafeBufferPointer { p in
                    vDSP_measqv(p.baseAddress!, 1, &energy, vDSP_Length(hop))
                }
                envelope.append(energy)
                carry.removeFirst(hop)
            }
        }
        reader.cancelReading()

        guard envelope.count > 64 else { return nil }

        // « Onset strength » : différence première positive
        var onset = [Float](repeating: 0, count: envelope.count)
        for i in 1..<envelope.count {
            let d = envelope[i] - envelope[i - 1]
            onset[i] = d > 0 ? d : 0
        }
        // Centrage (retrait de la moyenne), en place
        var mean: Float = 0
        vDSP_meanv(onset, 1, &mean, vDSP_Length(onset.count))
        var negMean = -mean
        onset.withUnsafeMutableBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            vDSP_vsadd(base, 1, &negMean, base, 1, vDSP_Length(buf.count))
        }

        // Autocorrélation sur la plage de lags correspondant à 70–180 BPM
        let fr = sampleRate / Double(hop)
        let minLag = max(1, Int(fr * 60.0 / 180.0))
        let maxLag = min(onset.count - 1, Int(fr * 60.0 / 70.0))
        guard maxLag > minLag else { return nil }

        var bestLag = minLag
        var bestVal: Float = -.greatestFiniteMagnitude
        onset.withUnsafeBufferPointer { p in
            guard let base = p.baseAddress else { return }
            for lag in minLag...maxLag {
                let n = onset.count - lag
                var sum: Float = 0
                vDSP_dotpr(base, 1, base + lag, 1, &sum, vDSP_Length(n))
                if sum > bestVal { bestVal = sum; bestLag = lag }
            }
        }
        guard bestVal > 0, bestLag > 0 else { return nil }

        var bpm = 60.0 * fr / Double(bestLag)
        while bpm < 90 { bpm *= 2 }
        while bpm > 180 { bpm /= 2 }
        return bpm
    }

    /// Durée d'un battement (en secondes) pour un BPM donné.
    static func beatDuration(bpm: Double) -> Double {
        guard bpm > 0 else { return 0.5 }
        return 60.0 / bpm
    }
}
