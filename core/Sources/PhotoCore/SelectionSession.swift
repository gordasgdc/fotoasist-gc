import Foundation
import Combine

public enum PhotoFilter: String, CaseIterable, Sendable { case all, check, keep, reject, favorites }
/// Filtru pe INDICII (nu pe decizii): arată cadrele la care un indiciu experimental sugerează o verificare. Nu schimbă decizii, nu respinge nimic; fotografiile ascunse de filtru nu primesc acțiuni.
public enum CueFilter: String, CaseIterable, Sendable { case none, clipping, tone, lessSharp, analysisMissing, possibleBlink, uncertainFace, noFaceFound }
public enum ViewMode: String, CaseIterable, Sendable { case grid, view, compare }

/// Starea unei sesiuni de selecție (logică pură, fără UI): navigare, filtre, selecție multiplă, comparație, decizii în lot cu anulare, ce trece la editare.
/// Aplicația (SwiftUI) doar o afișează și îi trimite comenzi; deciziile se scriu în catalog (nu lângă originale).
public final class SelectionSession: ObservableObject {
    public let catalog: Catalog
    @Published public private(set) var photos: [PhotoRecord] = []
    @Published public var filter: PhotoFilter = .all { didSet { normalizeCurrent() } }
    @Published public var cueFilter: CueFilter = .none { didSet { normalizeCurrent() } }
    private var cueIndex: [CueFilter: Set<Int64>]?
    @Published public var mode: ViewMode = .view
    @Published public private(set) var currentId: Int64?
    @Published public private(set) var selectedIds: Set<Int64> = []
    @Published public private(set) var pinnedId: Int64?
    @Published public private(set) var groups: [SuggestedGroup] = []
    @Published public var autoAdvance = true
    @Published public private(set) var albums: [Catalog.AlbumInfo] = []
    @Published public var albumFilter: Int64? { didSet { loadAlbumMembers(); normalizeCurrent() } }   // albumul ales ca filtru (se păstrează la schimbarea etapei)
    @Published public private(set) var albumMembers: Set<Int64> = []
    @Published public var detail100 = false      // vizualizare la 100% (încărcată la cerere din cameră/RAW)
    /// Mod de selecție multiplă VIZIBIL (casete de bifat): un clic pe o fotografie o adaugă/scoate din selecție, fără taste speciale. Command/Shift rămân valabile oricând.
    @Published public var multiSelect = false
    /// Ultima acțiune de lot, în cuvinte (feedback vizibil: ce s-a schimbat și pe câte fotografii).
    @Published public private(set) var lastAction: String?

    public init(catalog: Catalog) throws { self.catalog = catalog; try reload(); currentId = visible.first?.id }

    public func reload() throws { cueIndex = nil; photos = try catalog.photos(); groups = try catalog.groups(); albums = (try? catalog.albums()) ?? []; if let a = albumFilter, !albums.contains(where: { $0.id == a }) { albumFilter = nil }; loadAlbumMembers(); normalizeCurrent() }
    func loadAlbumMembers() { albumMembers = albumFilter.flatMap { try? catalog.albumPhotoIds($0) } ?? [] }
    public var visible: [PhotoRecord] {
        let base = albumFilter == nil ? photos : photos.filter { albumMembers.contains($0.id) }
        let b2: [PhotoRecord] = cueFilter == .none ? base : { let ids = cueSet(cueFilter); return base.filter { ids.contains($0.id) } }()
        return decisionFiltered(b2)
    }
    private func decisionFiltered(_ base: [PhotoRecord]) -> [PhotoRecord] {
        switch filter {
        case .all: return base
        case .favorites: return base.filter { $0.favorite }
        case .check: return base.filter { $0.decision == .check }
        case .keep: return base.filter { $0.decision == .keep }
        case .reject: return base.filter { $0.decision == .reject }
        }
    }
    /// Indicele indiciilor (calculat o dată pe încărcare): semnale din catalog + analiza de fețe, dacă există. Cadrele neanalizate NU intră la «fețe incerte»/«fără față» (nu știm), ci doar la «analiză neefectuată».
    func cueSet(_ f: CueFilter) -> Set<Int64> {
        if cueIndex == nil {
            var idx: [CueFilter: Set<Int64>] = [:]; var sig: [Int64: Signals] = [:]
            for p in photos { if let s = (try? catalog.signals(photoId: p.id)) ?? nil { sig[p.id] = s } }
            for p in photos {
                let s = sig[p.id]; let cues = ExposureCues.exposure(s)
                if s == nil { idx[.analysisMissing, default: []].insert(p.id) }
                if let s = s { if s.clipHighPct >= ExposureCues.clipNoticePct || s.clipLowPct >= ExposureCues.clipNoticePct { idx[.clipping, default: []].insert(p.id) }
                    if cues.contains(where: { $0.kind == .exposure }) && !(s.clipHighPct >= ExposureCues.clipNoticePct || s.clipLowPct >= ExposureCues.clipNoticePct) { idx[.tone, default: []].insert(p.id) } }
                if let g = group(of: p.id), ExposureCues.sharpness(own: sig[p.id], groupSignals: g.memberIds.compactMap { sig[$0] }) != nil { idx[.lessSharp, default: []].insert(p.id) }
                if let fr = catalog.faceResult(for: p) {
                    let obs = fr.faces.map(FaceAnalyzer.observation)
                    if obs.isEmpty { idx[.noFaceFound, default: []].insert(p.id) }
                    if obs.contains(where: { FaceAnalyzer.blinkSuggestion($0).state == .closed }) { idx[.possibleBlink, default: []].insert(p.id) }
                    if obs.contains(where: { FaceAnalyzer.blinkSuggestion($0).state == .uncertain || $0.box.height < FaceQualityCompare.minFaceHeight }) { idx[.uncertainFace, default: []].insert(p.id) }
                }
            }
            cueIndex = idx
        }
        return cueIndex?[f] ?? []
    }
    public func cueCount(_ f: CueFilter) -> Int { f == .none ? photos.count : cueSet(f).count }
    public var current: PhotoRecord? { photos.first { $0.id == currentId } }
    public var pinned: PhotoRecord? { photos.first { $0.id == pinnedId } }
    public var counts: (total: Int, keep: Int, reject: Int, check: Int, favorites: Int) {
        (photos.count, photos.filter { $0.decision == .keep }.count, photos.filter { $0.decision == .reject }.count, photos.filter { $0.decision == .check }.count, photos.filter { $0.favorite }.count)
    }
    public func count(for f: PhotoFilter) -> Int { switch f { case .all: return counts.total; case .check: return counts.check; case .keep: return counts.keep; case .reject: return counts.reject; case .favorites: return counts.favorites } }
    public func group(of id: Int64) -> SuggestedGroup? { groups.first { $0.memberIds.contains(id) } }

    // navigare și selecție
    public func select(_ id: Int64) { if photos.contains(where: { $0.id == id }) { currentId = id } }
    public func move(_ delta: Int) {
        let v = visible; guard !v.isEmpty else { return }
        let i = v.firstIndex { $0.id == currentId } ?? 0; currentId = v[max(0, min(v.count - 1, i + delta))].id
    }
    /// Un clic pe o fotografie: în modul de selecție multiplă comută bifa; altfel Command = comută, Shift = interval, simplu = o singură fotografie curentă.
    public func tap(_ id: Int64, command: Bool = false, shift: Bool = false) {
        if shift { selectRange(to: id) } else if command || multiSelect { toggleSelected(id); if !multiSelect || currentId == nil { select(id) } } else { select(id) }
    }
    /// Selectează TOATE fotografiile vizibile acum (după filtru / album), nu pe cele ascunse.
    public func selectAllVisible() { selectedIds = Set(visible.map { $0.id }) }
    public func deselectAll() { selectedIds = [] }
    /// Selecția efectivă (doar ce se vede), în ordinea listei.
    public var selectedVisible: [PhotoRecord] { visible.filter { selectedIds.contains($0.id) } }
    /// Cu câte fotografii se aplică o acțiune de lot: selecția dacă există, altfel doar cadrul curent. Mereu numai fotografii VIZIBILE.
    public var targetCount: Int { targets.count }
    public var targetsAreSelection: Bool { !selectedIds.isEmpty }
    /// Ce decizii au acum țintele (ca utilizatorul să vadă ce schimbă o acțiune de lot).
    public var targetMix: (keep: Int, reject: Int, check: Int) {
        let t = Set(targets); let ps = photos.filter { t.contains($0.id) }
        return (ps.filter { $0.decision == .keep }.count, ps.filter { $0.decision == .reject }.count, ps.filter { $0.decision == .check }.count)
    }
    /// Descrierea listei curente: «Se văd 103 din 136 · filtru: De verificat · album: X».
    public var visibleSummary: (shown: Int, total: Int, filter: PhotoFilter, album: String?) { (visible.count, photos.count, filter, albumFilter.flatMap { id in albums.first { $0.id == id }?.name }) }
    public func toggleSelected(_ id: Int64) { if selectedIds.contains(id) { selectedIds.remove(id) } else { selectedIds.insert(id) } }
    public func selectRange(to id: Int64) {
        let v = visible.map { $0.id }; guard let a = v.firstIndex(of: currentId ?? id), let b = v.firstIndex(of: id) else { return }
        selectedIds = Set(v[min(a, b)...max(a, b)])
    }
    public func clearSelection() { selectedIds = [] }
    /// Selecția nu poate conține fotografii care nu se văd în lista curentă (altfel «Scoate din catalog…» ar acționa pe fotografii ascunse).
    public func restrictSelection(to visible: Set<Int64>) { let r = selectedIds.intersection(visible); if r != selectedIds { selectedIds = r } }
    public func pinCurrent() { pinnedId = currentId }
    public func clearPin() { pinnedId = nil }

    // decizii (tinta = selecția multiplă dacă există, altfel cadrul curent)
    /// Ținte: selecția (doar ce e vizibil) dacă există, altfel cadrul curent. Nu acționează niciodată pe fotografii ascunse de filtru.
    private var targets: [Int64] { selectedIds.isEmpty ? (currentId.map { [$0] } ?? []) : visible.map { $0.id }.filter { selectedIds.contains($0) } }
    public func apply(_ d: Decision) throws {
        let t = targets; guard !t.isEmpty else { return }
        let hadSelection = !selectedIds.isEmpty
        try catalog.setDecision(d, photoIds: t); try reload()
        let nm: String; switch d { case .keep: nm = L("Păstrate"); case .reject: nm = "Respinse"; case .check: nm = "De verificat" }
        lastAction = LF("%@ «%@» (decizie reversibilă, ⌘Z anulează)", t.count == 1 ? "1 fotografie marcată" : "\(t.count) fotografii marcate", nm)
        if autoAdvance && !hadSelection && mode != .grid { move(1) }
        if hadSelection { selectedIds = [] }
    }
    public func toggleFavorite() throws { guard let c = current else { return }; try catalog.setFavorite(!c.favorite, photoId: c.id); try reload() }
    public func setRating(_ n: Int) throws { guard let c = current else { return }; try catalog.setRating(c.rating == n ? 0 : n, photoId: c.id); try reload() }
    @discardableResult public func undo() throws -> Int { let n = try catalog.undoLastDecisionBatch(); try reload(); return n }

    // albume (colecții virtuale): ținta = selecția multiplă dacă există, altfel cadrul curent
    public var albumTargets: [Int64] { targets }
    @discardableResult public func createAlbum(_ name: String, addTargets: Bool) throws -> Int64 { let id = try catalog.createAlbum(name); if addTargets { try catalog.addToAlbum(id, photoIds: targets) }; try reload(); return id }
    public func renameAlbum(_ id: Int64, _ name: String) throws { try catalog.renameAlbum(id, to: name); try reload() }
    public func deleteAlbum(_ id: Int64) throws { try catalog.deleteAlbum(id); try reload() }
    public func addTargets(toAlbum id: Int64) throws { let n = targets.count; try catalog.addToAlbum(id, photoIds: targets); try reload(); lastAction = LF("%@ în albumul «%@»", n == 1 ? "1 fotografie adăugată" : "\(n) fotografii adăugate", albums.first { $0.id == id }?.name ?? "") }
    public func removeTargets(fromAlbum id: Int64) throws { let n = targets.count; try catalog.removeFromAlbum(id, photoIds: targets); try reload(); lastAction = LF("%@ din albumul «%@» (au rămas în catalog și pe disc)", n == 1 ? "1 fotografie scoasă" : "\(n) fotografii scoase", albums.first { $0.id == id }?.name ?? "") }
    public func albums(of photoId: Int64) -> [Catalog.AlbumInfo] { let ids = Set((try? catalog.albumIds(of: photoId)) ?? []); return albums.filter { ids.contains($0.id) } }
    /// Ce trece la editare: păstratele (implicit) sau TOATE (selecția a fost sărită). Nu șterge/mută nimic.
    public func editQueue(allPhotos: Bool) -> [PhotoRecord] { allPhotos ? photos : photos.filter { $0.decision == .keep } }

    private func normalizeCurrent() {
        let v = visible
        restrictSelection(to: Set(v.map { $0.id }))   // filtrul / albumul / reîncărcarea nu lasă în selecție fotografii care nu se văd
        if let c = currentId, v.contains(where: { $0.id == c }) { return }
        currentId = v.first?.id ?? (photos.contains { $0.id == currentId } ? currentId : photos.first?.id)
    }
}
