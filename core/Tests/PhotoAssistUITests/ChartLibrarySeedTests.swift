import XCTest
import PhotoAccess
@testable import PhotoAssistUI
import PhotoCore
import PhotoRaw
import PhotoResolve

/// Pregătește o bibliotecă de probă (pe extern) cu fotografiile chart-ului, importate prin ACELAȘI importator ca aplicația (originalele doar citite), și poziționează grila (stare de sesiune, nu corecție).
/// Rulează doar cu GDC_PA_CHART_DIR + GDC_PA_SEED_LIBRARY; nu are rol de regresie.
@MainActor
final class ChartLibrarySeedTests: XCTestCase {
    func testSeedChartLibrary() async throws {
        let e = ProcessInfo.processInfo.environment
        guard let dir = e["GDC_PA_CHART_DIR"], let lib = e["GDC_PA_SEED_LIBRARY"] else { throw XCTSkip("GDC_PA_CHART_DIR/GDC_PA_SEED_LIBRARY nesetate") }
        let m = try AppModel(libraryDir: URL(fileURLWithPath: lib), policy: DevOpenPolicy())
        await m.importFolder(URL(fileURLWithPath: dir))
        let photos = m.session.photos; print("[seed] importate \(photos.count)")
        let grids: [String: [(Double, Double)]] = ["_DSC0334": [(0.5017, 0.4592), (0.7083, 0.4592), (0.7083, 0.9267), (0.5017, 0.9267)], "_DSC0322": [(0.560, 0.387), (0.775, 0.387), (0.775, 0.874), (0.560, 0.874)], "_DSC0327": [(0.527, 0.375), (0.745, 0.375), (0.745, 0.859), (0.527, 0.859)], "_DSC0333": [(0.525, 0.464), (0.735, 0.464), (0.735, 0.934), (0.525, 0.934)], "_DSC0342": [(0.520, 0.456), (0.722, 0.456), (0.722, 0.916), (0.520, 0.916)]]
        for p in photos { let stem = ((p.path as NSString).lastPathComponent as NSString).deletingPathExtension
            guard let c = grids[stem] else { continue }
            var g = ChartGrid(); g.corners = c.map { CGPoint(x: $0.0, y: $0.1) }; g.rotation = 3; g.mirrored = false
            let st = ChartSessionState(model: .classicAfter2014, grid: g)
            if let d = try? JSONEncoder().encode(st), let s = String(data: d, encoding: .utf8) { try m.catalog.setSession("chart_session:\(p.id)", s) }
            print("[seed] \(stem) id=\(p.id)") }
    }
}
