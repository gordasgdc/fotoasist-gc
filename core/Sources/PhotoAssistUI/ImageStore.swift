import SwiftUI
import PhotoCore

/// Încarcă la cerere imaginile din PreviewCache (generează doar ce lipsește), pe o coadă serială; păstrează un NSCache în memorie.
public final class ImageStore: ObservableObject {
    public let cache: PreviewCache
    private let queue = DispatchQueue(label: "photoassist.imagestore")
    private let mem = NSCache<NSString, NSImage>()
    public init(cache: PreviewCache) { self.cache = cache }
    /// Singurul punct de acces la PreviewCache (serial): evită cursele pe contoare/fișiere.
    public func run<T>(_ body: @escaping (PreviewCache) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { c in queue.async { c.resume(with: Result { try body(self.cache) }) } }
    }
    public func image(for photo: PhotoRecord, kind: PreviewKind) async -> NSImage? {
        let key = "\(photo.id)_\(kind.rawValue)_\(photo.mtimeNs)" as NSString
        if let i = mem.object(forKey: key) { return i }
        let url: URL? = await withCheckedContinuation { c in queue.async { c.resume(returning: try? self.cache.url(for: photo, kind: kind)) } }
        guard let u = url, let img = NSImage(contentsOf: u) else { return nil }
        mem.setObject(img, forKey: key); return img
    }
}

struct PhotoImage: View {
    let photo: PhotoRecord; let kind: PreviewKind; var fill = false; var compact = false
    @EnvironmentObject var store: ImageStore
    @State private var img: NSImage?; @State private var failure: String?
    var body: some View {
        // Fără dimensiune intrinsecă: imaginea se potrivește în spațiul oferit (altfel previzualizarea de 1400 px lărgește fereastra).
        Color.clear.overlay(
            Group {
                if let img = img { Image(nsImage: img).resizable().aspectRatio(contentMode: fill ? .fill : .fit) }
                else if let f = failure, compact { Rectangle().fill(Theme.panel2).overlay(VStack(spacing: 3) { Image(systemName: "exclamationmark.triangle").foregroundColor(Theme.check); Text(L("Fără previzualizare")).font(Theme.f(10.5, weight: .semibold)).foregroundColor(Theme.muted).lineLimit(1) }).help(f) }
                else if let f = failure { Rectangle().fill(Theme.panel2).overlay(VStack(spacing: 4) { Image(systemName: "exclamationmark.triangle").foregroundColor(Theme.check); Text(L("Fără previzualizare")).font(Theme.f(12, weight: .semibold)); Text(f).font(Theme.f(11)).foregroundColor(Theme.muted).multilineTextAlignment(.center).lineLimit(3) }.padding(8)) }
                else { Rectangle().fill(Theme.panel2).overlay(ProgressView().controlSize(.small)) }
            }
        ).clipped()
        .task(id: photo.id) {
            failure = nil; img = await store.image(for: photo, kind: kind)
            if img == nil { let path = photo.path, size = photo.size   // motivul real, cu dovadă; fișierul rămâne neatins în catalog
                let h = await Task.detached { FileHealth.inspect(path: path, recordedSize: size, stabilityDelay: 0) }.value
                failure = h.kind == .ok ? L("Previzualizarea nu s-a putut genera (decodorul nu a putut citi fișierul).") : "\(h.kind.label): \(h.evidence)" }
        }
    }
}
