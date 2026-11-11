import Foundation

/// Ceas monoton pentru toate intervalele de interacțiune (nu se schimbă la ajustarea orei sistemului).
enum MonoClock { static var now: Double { ProcessInfo.processInfo.systemUptime } }

/// Momentele unei cereri, scrise pe coada de procesare și citite după `await` (același ceas monoton).
final class StageBox: @unchecked Sendable { var tEnq = 0.0, tStart = 0.0, tDone = 0.0 }

/// Ocuparea firului principal, măsurată SEPARAT de durata cadrului: un temporizator de 8 ms pe firul principal; întârzierea fiecărei declanșări = cât timp a fost firul principal indisponibil.
/// Pornește la primul gest și se oprește singur după 2 s fără gesturi.
@MainActor final class StallMonitor {
    private var timer: DispatchSourceTimer?; private var deadline = 0.0; private var last = 0.0
    private(set) var samples: [(t: Double, late: Double)] = []   // ultimele 1500
    static let interval = 0.008
    func touch() {
        deadline = MonoClock.now + 2.0
        guard timer == nil else { return }
        last = MonoClock.now
        let t = DispatchSource.makeTimerSource(queue: .main); t.schedule(deadline: .now() + Self.interval, repeating: Self.interval, leeway: .milliseconds(1))
        t.setEventHandler { [weak self] in
            guard let self = self else { return }; let n = MonoClock.now; let late = max(0, n - self.last - Self.interval); self.last = n
            self.samples.append((n, late)); if self.samples.count > 1500 { self.samples.removeFirst(self.samples.count - 1500) }
            if n > self.deadline { self.timer?.cancel(); self.timer = nil }
        }
        t.resume(); timer = t
    }
    /// n eșantioane, mediană, p95, maxim (ms) și fracția de timp cu firul principal blocat > 16 ms, în intervalul dat.
    func stats(from a: Double, to b: Double) -> (n: Int, p50: Double, p95: Double, max: Double, over16: Int) {
        let xs = samples.filter { $0.t >= a && $0.t <= b }.map { $0.late * 1000 }.sorted(); guard !xs.isEmpty else { return (0, 0, 0, 0, 0) }
        return (xs.count, xs[xs.count / 2], xs[min(xs.count - 1, Int(Double(xs.count) * 0.95))], xs.last!, xs.filter { $0 > 16 }.count)
    }
}
