import Foundation
import GameKit

/// Every one-shot sound effect. The file name is also the bundle override name (`pop.caf` replaces "pop").
enum Sfx: String, CaseIterable {
    case SWAP = "swap"
    case SWAP_BACK = "swap_back"
    case POP = "pop"
    case SPECIAL = "special"
    case STRIPED = "striped"
    case WRAPPED = "wrapped"
    case COLOR_BOMB = "color_bomb"
    case LAND = "land"
    case CLICK = "click"
    case STAR = "star"
    case WIN = "win"
    case LOSE = "lose"
    case JELLY = "jelly"
    case FROSTING = "frosting"
    case WHOOSH = "whoosh"
    case UNLOCK = "unlock"

    var fileName: String { rawValue }
    static var entries: [Sfx] { allCases }
}

enum Music: String, CaseIterable {
    case MENU = "music_menu"
    case GAME = "music_game"

    var fileName: String { rawValue }
    static var entries: [Music] { allCases }
}

/**
 * Procedural sound bank: synthesises every effect and two seamless music loops (Kotlin `SynthBank`).
 *
 * iOS renders at 48 kHz float (GameKit `Synth.sampleRate`) instead of Android's 44.1 kHz effects / 32 kHz music.
 * Every recipe is the Kotlin one; all timing is in seconds and every per-sample coefficient (filters,
 * envelopes, phase steps) is derived from the sample rate, so the sounds are identical but full-bandwidth.
 * The two sample-count constants Android hard-coded (crunch grain every 180 samples @ 44.1 kHz and the
 * 64-sample end fade) are converted to the same durations at 48 kHz.
 * Rendered audio is cached as raw float32 in Caches/audio/v<VERSION>-48k so later launches are instant.
 */
enum SynthBank {
    private static let VERSION = 1
    /// Sample rate of everything rendered here (Android: SR = 44100 for effects, MUSIC_SR = 32000 for music).
    static let SR = Int(GameKit.Synth.sampleRate)
    private static let ANDROID_SFX_SR: Double = 44100

    /// Semitone offsets for the cascade chime (pentatonic steps).
    static let CHIME_STEPS: [Int] = [0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24]

    static func chimeName(_ i: Int) -> String { "chime_\(i)" }

    static func dir() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("audio/v\(VERSION)-\(SR / 1000)k", isDirectory: true)
    }

    static func file(_ name: String) -> URL { dir().appendingPathComponent("\(name).f32") }

    private struct Job {
        let name: String
        let isMusic: Bool
        let build: () -> [Float]
    }

    private static func jobs() -> [Job] {
        var list: [Job] = []
        for s in Sfx.allCases { list.append(Job(name: s.fileName, isMusic: false) { sfx(s) }) }
        for (i, st) in CHIME_STEPS.enumerated() { list.append(Job(name: chimeName(i), isMusic: false) { chime(st) }) }
        list.append(Job(name: Music.MENU.fileName, isMusic: true) { menuLoop() })
        list.append(Job(name: Music.GAME.fileName, isMusic: true) { gameLoop() })
        return list
    }

    /// Every sound name: effects, chimes and music.
    static var allNames: [String] {
        Sfx.allCases.map(\.fileName) + CHIME_STEPS.indices.map(chimeName) + Music.allCases.map(\.fileName)
    }

    // MARK: in-memory store (filled by ensureGenerated, consumed by AudioManager.loadAll)

    private static let lock = NSLock()
    private static var rendered: [String: [Float]] = [:]

    /// Samples for `name` (48 kHz mono): from memory, else the cache file, else rendered now.
    static func samples(_ name: String) -> [Float]? {
        lock.lock()
        if let s = rendered[name] { lock.unlock(); return s }
        lock.unlock()
        if let s = readCache(name) { return s }
        guard let job = jobs().first(where: { $0.name == name }) else { return nil }
        let pcm = job.build()
        writeCache(name, pcm)
        return pcm
    }

    /// Frees the in-memory copies once the audio engine owns the buffers.
    static func releaseMemory() {
        lock.lock()
        rendered.removeAll()
        lock.unlock()
    }

    /**
     * Generates (or loads from cache) every sound, reporting progress 0..1 from worker threads.
     * Safe to call repeatedly. Runs entirely off the main thread.
     */
    static func ensureGenerated(onProgress: @escaping @Sendable (Float) -> Void = { _ in }) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                try? FileManager.default.createDirectory(at: dir(), withIntermediateDirectories: true)
                // The two long music loops start first so they overlap with the short effects.
                let all = jobs().enumerated().sorted { a, b in
                    a.element.isMusic != b.element.isMusic ? a.element.isMusic : a.offset < b.offset
                }.map(\.element)
                let counter = ProgressCounter()
                DispatchQueue.concurrentPerform(iterations: all.count) { i in
                    let job = all[i]
                    let pcm: [Float]
                    if let cached = readCache(job.name) {
                        pcm = cached
                    } else {
                        pcm = job.build()
                        writeCache(job.name, pcm)
                    }
                    lock.lock()
                    rendered[job.name] = pcm
                    lock.unlock()
                    onProgress(Float(counter.increment()) / Float(all.count))
                }
                cont.resume()
            }
        }
    }

    private static func readCache(_ name: String) -> [Float]? {
        guard let data = try? Data(contentsOf: file(name), options: .mappedIfSafe), data.count >= 4, data.count % 4 == 0 else { return nil }
        var out = [Float](repeating: 0, count: data.count / 4)
        out.withUnsafeMutableBytes { dst in _ = data.copyBytes(to: dst) }
        return out
    }

    private static func writeCache(_ name: String, _ pcm: [Float]) {
        let tmp = dir().appendingPathComponent("\(name).tmp")
        let data = pcm.withUnsafeBufferPointer { Data(buffer: $0) }
        do {
            try data.write(to: tmp, options: .atomic)
            let dst = file(name)
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.moveItem(at: tmp, to: dst)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
        }
    }

    /// Renders one sound without touching the cache (tests / debug).
    static func render(_ name: String) -> [Float]? { jobs().first(where: { $0.name == name })?.build() }

    // ------------------------------------------------------------------ effects

    private static func sfx(_ s: Sfx) -> [Float] {
        switch s {
        case .SWAP: return render(0.2) { s in
            s.tone(0, 0.14, 520, 980, .SINE, 0.7, decay: 14)
            s.noise(0, 0.05, 0.06, decay: 40, hp: 2000)
        }
        case .SWAP_BACK: return render(0.26) { s in
            s.tone(0, 0.1, 820, 600, .SINE, 0.6, decay: 10)
            s.tone(0.1, 0.13, 640, 420, .SINE, 0.6, decay: 10)
        }
        case .POP: return render(0.16) { s in
            s.tone(0, 0.12, 1100, 280, .SINE, 0.8, decay: 20)
            s.tone(0, 0.018, 2600, 2400, .TRIANGLE, 0.22, decay: 80)
            s.noise(0, 0.012, 0.3, decay: 150, hp: 1500)
        }
        case .SPECIAL: return render(1.2) { s in
            for (i, st) in [0, 4, 7, 12, 16].enumerated() { s.bell(Float(i) * 0.06, 76 + st, 0.32, decay: 5, dur: 0.8) }
        }
        case .STRIPED: return render(0.5) { s in
            s.tone(0, 0.4, 1800, 180, .SAW, 0.35, decay: 5)
            s.tone(0, 0.4, 900, 120, .SINE, 0.45, decay: 5)
            s.noise(0, 0.32, 0.22, decay: 7, lp: 4000, hp: 900)
        }
        case .WRAPPED: return render(0.65) { s in
            s.tone(0, 0.5, 160, 38, .SINE, 1.0, decay: 6)
            s.noise(0, 0.45, 0.55, decay: 8, lp: 700)
        }
        case .COLOR_BOMB: return render(1.6) { s in
            let r = JavaRandom(77)
            for i in 0..<14 { s.bell(Float(i) * 0.045, 84 + r.nextInt(17), 0.2, decay: 7, dur: 0.6) }
            s.tone(0, 0.75, 220, 880, .TRIANGLE, 0.3, attack: 0.05, decay: 2)
        }
        case .LAND: return render(0.08) { s in
            s.tone(0, 0.06, 420, 300, .SINE, 0.25, decay: 40)
        }
        case .CLICK: return render(0.09) { s in
            s.tone(0, 0.07, 1300, 900, .SINE, 0.6, decay: 30)
            s.noise(0, 0.012, 0.16, decay: 120, hp: 2500)
        }
        case .STAR: return render(1.0) { s in
            s.bell(0, 84, 0.45, decay: 4, dur: 0.9)
            s.bell(0.08, 91, 0.35, decay: 4.5, dur: 0.85)
        }
        case .WIN: return render(2.2) { s in
            for (i, m) in [72, 76, 79, 84, 88].enumerated() { s.bell(Float(i) * 0.11, m, 0.38, decay: 3.5, dur: 1.1) }
            for m in [60, 64, 67, 72] {
                s.tone(0.55, 1.5, midiHz(m), midiHz(m), .TRIANGLE, 0.16, attack: 0.03, decay: 2.2)
            }
        }
        case .LOSE: return render(1.3) { s in
            for (i, m) in [67, 64, 60, 55].enumerated() {
                s.tone(Float(i) * 0.22, 0.4, midiHz(m), midiHz(m) * 0.985, .TRIANGLE, 0.45, attack: 0.01, decay: 4)
            }
        }
        case .JELLY: return render(0.22) { s in
            s.tone(0, 0.18, 280, 720, .SINE, 0.55, decay: 10, vibratoHz: 38, vibratoDepth: 0.08)
            s.tone(0, 0.12, 560, 1200, .TRIANGLE, 0.15, decay: 18)
        }
        case .FROSTING: return render(0.24) { s in s.crunch(0, 0.2, 0.75) }
        case .WHOOSH: return render(0.6) { s in s.swell(0, 0.55, 0.6) }
        case .UNLOCK: return render(1.0) { s in
            s.bell(0, 79, 0.42, decay: 4, dur: 0.8)
            s.bell(0.12, 86, 0.42, decay: 4, dur: 0.8)
        }
        }
    }

    private static func chime(_ semitones: Int) -> [Float] {
        render(0.9) { s in s.bell(0, 72 + semitones, 0.55, decay: 4.5, dur: 0.85) }
    }

    // ------------------------------------------------------------------ music

    private struct Chord {
        let root: Int
        let tones: [Int]
    }

    private static func menuLoop() -> [Float] {
        loop(bpm: 92, chords: [
            Chord(root: 41, tones: [53, 57, 60]), // F
            Chord(root: 43, tones: [55, 59, 62]), // G
            Chord(root: 40, tones: [52, 55, 59]), // Em
            Chord(root: 45, tones: [57, 60, 64]), // Am
        ], seed: 11)
    }

    private static func gameLoop() -> [Float] {
        loop(bpm: 112, chords: [
            Chord(root: 36, tones: [60, 64, 67]), // C
            Chord(root: 45, tones: [57, 60, 64]), // Am
            Chord(root: 41, tones: [53, 57, 60]), // F
            Chord(root: 43, tones: [55, 59, 62]), // G
        ], seed: 29)
    }

    private static func loop(bpm: Float, chords: [Chord], seed: Int64) -> [Float] {
        let beat = 60 / bpm
        let beats = chords.count * 8 // 2 bars per chord
        let n = Kt.roundToInt(Float(beats) * beat * Float(SR))
        let dry = Synth(n, SR, wrap: true)
        let wet = Synth(n, SR, wrap: true)
        let rnd = JavaRandom(seed)
        let penta = [72, 74, 76, 79, 81, 84]
        let pattern = [0, 1, 2, 1]
        for (ci, ch) in chords.enumerated() {
            let t0 = Float(ci * 8) * beat
            // Triangle pad, slow attack.
            for m in ch.tones {
                dry.tone(t0, 8 * beat, midiHz(m), midiHz(m), .TRIANGLE, 0.075, attack: 0.45, decay: 0.12, tailFrac: 0.18)
            }
            for b in 0..<8 {
                let tb = t0 + Float(b) * beat
                let inBar = b % 4
                if inBar == 0 || inBar == 2 {
                    dry.tone(tb, beat * 1.7, midiHz(ch.root), midiHz(ch.root), .SINE, 0.32, attack: 0.008, decay: 2.4)
                    dry.tone(tb, 0.24, 130, 42, .SINE, 0.6, attack: 0.002, decay: 14)
                } else {
                    dry.noise(tb, 0.12, 0.2, decay: 26, lp: 3500, hp: 900)
                }
                dry.noise(tb + beat * 0.5, 0.035, 0.05, decay: 70, hp: 6000)
                // Arpeggio eighth notes through the chord tones.
                for e in 0..<2 {
                    let m = ch.tones[pattern[(b * 2 + e) % 4]] + 12
                    wet.tone(tb + Float(e) * beat * 0.5, beat * 0.45, midiHz(m), midiHz(m), .SINE, 0.07, attack: 0.005, decay: 7)
                }
                // Sparse pentatonic bell melody.
                if rnd.nextFloat() < 0.32 {
                    wet.bell(tb + (rnd.nextBoolean() ? 0 : beat * 0.5), penta[rnd.nextInt(penta.count)], 0.085, decay: 3.5, dur: beat * 1.6)
                }
            }
        }
        // Circular feedback delay: 3/4 beat, 0.33 feedback, 2 passes, wraps around the loop seamlessly.
        let d = Kt.roundToInt(beat * 0.75 * Float(SR))
        var out = [Float](repeating: 0, count: n)
        wet.data.withUnsafeBufferPointer { w in
            dry.data.withUnsafeBufferPointer { dr in
                out.withUnsafeMutableBufferPointer { o in
                    for i in 0..<n {
                        var v = w[i]
                        var g: Float = 0.33
                        for pass in 1...2 {
                            v += w[((i - pass * d) % n + n) % n] * g
                            g *= 0.33
                        }
                        o[i] = dr[i] + v
                    }
                }
            }
        }
        normalise(&out, 0.7, fade: false)
        return out
    }

    // ------------------------------------------------------------------ synthesis core

    fileprivate enum Wave { case SINE, TRIANGLE, SQUARE, SAW }

    fileprivate static func midiHz(_ m: Int) -> Float { Float(440.0 * Foundation.pow(2.0, Double(m - 69) / 12.0)) }

    private static func render(_ seconds: Float, _ block: (Synth) -> Void) -> [Float] {
        let s = Synth(Kt.roundToInt(seconds * Float(SR)), SR, wrap: false)
        block(s)
        var d = s.data
        normalise(&d, 0.85, fade: true)
        return d
    }

    fileprivate final class Synth {
        let n: Int
        let sr: Int
        let wrap: Bool
        var data: [Float]
        private let rnd = JavaRandom(Int64(1234))

        init(_ n: Int, _ sr: Int, wrap: Bool) {
            self.n = max(1, n)
            self.sr = sr
            self.wrap = wrap
            data = [Float](repeating: 0, count: max(1, n))
        }

        /// Runs `body` with a pointer to the data and the add rule (wrap or clip), without per-sample bounds checks.
        @inline(__always)
        private func withSink(_ body: (UnsafeMutablePointer<Float>) -> Void) {
            data.withUnsafeMutableBufferPointer { body($0.baseAddress!) }
        }

        @inline(__always)
        private func add(_ p: UnsafeMutablePointer<Float>, _ i: Int, _ v: Float) {
            if wrap {
                p[((i % n) + n) % n] += v
            } else if i >= 0 && i < n {
                p[i] += v
            }
        }

        /// Oscillator with phase accumulation, linear pitch sweep and attack × exp(−decay·t) envelope plus an 8 % tail.
        func tone(
            _ start: Float, _ dur: Float, _ f0: Float, _ f1: Float, _ wave: Wave, _ amp: Float,
            attack: Float = 0.004, decay: Float = 6, tailFrac: Float = 0.08,
            vibratoHz: Float = 0, vibratoDepth: Float = 0
        ) {
            let len = Kt.roundToInt(dur * Float(sr))
            let s0 = Kt.roundToInt(start * Float(sr))
            guard len > 0 else { return }
            var env = Envelope(len, sr, attack, decay, tailFrac)
            var phase: Float = 0
            let invSr = 1 / Float(sr)
            withSink { p in
                for k in 0..<len {
                    let prog = Float(k) / Float(len)
                    var f = f0 + (f1 - f0) * prog
                    if vibratoHz > 0 { f *= 1 + vibratoDepth * SynthBank.sineTable(vibratoHz * Float(k) * invSr) }
                    phase += f * invSr
                    if phase >= 1 { phase -= phase.rounded(.down) }
                    let o: Float
                    switch wave {
                    case .SINE: o = SynthBank.sineTable(phase)
                    case .TRIANGLE: o = 1 - 4 * abs(phase - 0.5)
                    case .SQUARE: o = tanhf(3 * SynthBank.sineTable(phase)) / 0.99505 * 0.6
                    case .SAW: o = (2 * phase - 1) * 0.6
                    }
                    add(p, s0 + k, o * amp * env.next(k))
                }
            }
        }

        /// White noise through optional one-pole low-pass and high-pass filters.
        func noise(_ start: Float, _ dur: Float, _ amp: Float, decay: Float = 10, lp: Float = 0, hp: Float = 0, attack: Float = 0.001) {
            let len = Kt.roundToInt(dur * Float(sr))
            let s0 = Kt.roundToInt(start * Float(sr))
            guard len > 0 else { return }
            let aLp: Float = lp > 0 ? onePole(lp) : 1
            let aHp: Float = hp > 0 ? onePole(hp) : 0
            var yl: Float = 0
            var yh: Float = 0
            var env = Envelope(len, sr, attack, decay, 0.08)
            withSink { p in
                for k in 0..<len {
                    let x = rnd.nextFloat() * 2 - 1
                    yl += aLp * (x - yl)
                    var v = yl
                    if hp > 0 {
                        yh += aHp * (v - yh)
                        v -= yh
                    }
                    add(p, s0 + k, v * amp * env.next(k))
                }
            }
        }

        /// Bell = sine partials ×1, ×2 (45 %), ×3.01 (20 %), ×4.2 (10 %), higher partials decay faster.
        func bell(_ start: Float, _ midi: Int, _ amp: Float, decay: Float = 4, dur: Float = 1) {
            let f = SynthBank.midiHz(midi)
            tone(start, dur, f, f, .SINE, amp, attack: 0.002, decay: decay)
            tone(start, dur, f * 2, f * 2, .SINE, amp * 0.45, attack: 0.002, decay: decay * 1.6)
            tone(start, dur, f * 3.01, f * 3.01, .SINE, amp * 0.2, attack: 0.002, decay: decay * 2.2)
            tone(start, dur, f * 4.2, f * 4.2, .SINE, amp * 0.1, attack: 0.002, decay: decay * 3)
        }

        /// Crunchy, granular noise burst (frosting). A new grain level every 180 samples at 44.1 kHz (4.08 ms).
        func crunch(_ start: Float, _ dur: Float, _ amp: Float) {
            let len = Kt.roundToInt(dur * Float(sr))
            let s0 = Kt.roundToInt(start * Float(sr))
            guard len > 0 else { return }
            let grainEvery = max(1, Int((180.0 * Double(sr) / SynthBank.ANDROID_SFX_SR).rounded()))
            let aHp = onePole(250)
            let aLp = onePole(5200)
            var yh: Float = 0
            var yl: Float = 0
            var grain: Float = 1
            var env = Envelope(len, sr, 0.001, 16, 0.1)
            withSink { p in
                for k in 0..<len {
                    if k % grainEvery == 0 { grain = rnd.nextFloat() > 0.45 ? 1 : 0.25 }
                    let x = rnd.nextFloat() * 2 - 1
                    yl += aLp * (x - yl)
                    yh += aHp * (yl - yh)
                    add(p, s0 + k, (yl - yh) * amp * grain * env.next(k))
                }
            }
        }

        /// Filtered noise swell with a rising cutoff (whoosh).
        func swell(_ start: Float, _ dur: Float, _ amp: Float) {
            let len = Kt.roundToInt(dur * Float(sr))
            let s0 = Kt.roundToInt(start * Float(sr))
            guard len > 0 else { return }
            var yl: Float = 0
            let pi = Float(Double.pi)
            withSink { p in
                for k in 0..<len {
                    let prog = Float(k) / Float(len)
                    let a = onePole(400 + 2800 * prog)
                    let x = rnd.nextFloat() * 2 - 1
                    yl += a * (x - yl)
                    add(p, s0 + k, yl * amp * Kt.sin(pi * prog))
                }
            }
        }

        @inline(__always)
        private func onePole(_ fc: Float) -> Float { Float(1.0 - Foundation.exp(-2.0 * Double.pi * Double(fc) / Double(sr))) }
    }

    /**
     * Linear attack × exp(−decay·t) with a click-free linear tail over the last [tailFrac].
     * The exponential is applied incrementally (one multiply per sample, in Double for accuracy at 48 kHz);
     * call [next] with k = 0, 1, 2…
     */
    fileprivate struct Envelope {
        private let len: Int
        private let attackSamples: Float
        private let step: Double
        private let tailStart: Int
        private let tailLen: Int
        private var level: Double = 1

        init(_ len: Int, _ sr: Int, _ attack: Float, _ decay: Float, _ tailFrac: Float) {
            self.len = len
            attackSamples = max(1, attack * Float(sr))
            step = Foundation.exp(-Double(decay) / Double(sr))
            tailStart = Kt.toInt(Float(len) * (1 - tailFrac))
            tailLen = max(1, len - tailStart)
        }

        @inline(__always)
        mutating func next(_ k: Int) -> Float {
            let a = min(1, Float(k) / attackSamples)
            let tail: Float = k >= tailStart ? max(0, Float(len - k) / Float(tailLen)) : 1
            let v = a * Float(level) * tail
            level *= step
            return v
        }
    }

    private static let TABLE_SIZE = 4096
    private static let SINE: [Float] = (0...TABLE_SIZE).map { Float(Foundation.sin(2.0 * Double.pi * Double($0) / Double(TABLE_SIZE))) }

    /// sin(2π·p) for p in cycles, linearly interpolated from a table.
    @inline(__always)
    fileprivate static func sineTable(_ p: Float) -> Float {
        let x = (p - p.rounded(.down)) * Float(TABLE_SIZE)
        let i = min(TABLE_SIZE - 1, max(0, Int(x)))
        let f = x - Float(i)
        return SINE.withUnsafeBufferPointer { t in t[i] + (t[i + 1] - t[i]) * f }
    }

    /// tanh soft clip scaled to [peak], plus a short fade-out for one-shots
    /// (Android: 64 samples at 44.1 kHz = 1.45 ms; same duration here).
    private static func normalise(_ d: inout [Float], _ peak: Float, fade: Bool) {
        var m: Float = 0
        for v in d { m = max(m, abs(v)) }
        if m < 1e-6 { return }
        let drive: Float = 1.4
        let norm = tanhf(drive)
        for i in d.indices { d[i] = tanhf(d[i] / m * drive) / norm * peak }
        if fade {
            let fadeLen = Int((64.0 * Double(SR) / ANDROID_SFX_SR).rounded())
            let f = min(fadeLen, d.count)
            for k in 0..<f { d[d.count - 1 - k] *= Float(k) / Float(f) }
        }
    }
}
