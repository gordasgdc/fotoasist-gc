import Foundation
import ImageIO

/// Inventar READ-ONLY al unui folder de fotografii: nu scrie nimic lângă originale (fără sidecar, fără cache în folderul sursă).
public enum Inventory {
    public static let rawExtensions: Set<String> = ["arw", "cr2", "cr3", "dng", "nef", "raf", "rw2", "orf"]
    public typealias Entry = (path: String, size: Int64, mtimeNs: Int64, camera: String?, capturedAt: Date?)

    /// Fișier AppleDouble (resource fork copiat pe volume non-HFS, uneori redenumit «_IMG…» sau «._IMG…»): are extensia RAW, dar nu e o fotografie (magic 0x00051607 / 0x00051600). Nu se importă.
    public static func isAppleDouble(path: String) -> Bool {
        guard let h = FileHandle(forReadingAtPath: path) else { return false }; defer { try? h.close() }
        guard let d = try? h.read(upToCount: 4), d.count == 4 else { return false }
        return d[0] == 0x00 && d[1] == 0x05 && d[2] == 0x16 && (d[3] == 0x07 || d[3] == 0x00)
    }
    public static func scan(directory: URL, recursive: Bool = false, readMetadata: Bool = true, rendered: Bool = false) throws -> [Entry] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        let en = fm.enumerator(at: directory, includingPropertiesForKeys: keys, options: recursive ? [.skipsHiddenFiles, .skipsPackageDescendants] : [.skipsHiddenFiles, .skipsSubdirectoryDescendants, .skipsPackageDescendants])   // doar directoare normale; fișierele comprimate/containere nu se deschid și nu se enumeră (filtru pe extensii RAW)
        var out: [Entry] = []
        while let u = en?.nextObject() as? URL {
            guard (rendered ? RenderedImage.extensions : rawExtensions).contains(u.pathExtension.lowercased()) else { continue }
            let v = try u.resourceValues(forKeys: Set(keys)); guard v.isRegularFile == true else { continue }
            if rendered { if u.lastPathComponent.hasPrefix("._") { continue } } else if isAppleDouble(path: u.path) { continue }
            var st = stat(); stat(u.path, &st)
            let mtimeNs = Int64(st.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(st.st_mtimespec.tv_nsec)
            var cam: String? = nil, when: Date? = nil
            if readMetadata, let src = CGImageSourceCreateWithURL(u as CFURL, nil), let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
                if !rendered, let tiff = p[kCGImagePropertyTIFFDictionary] as? [CFString: Any] { cam = tiff[kCGImagePropertyTIFFModel] as? String }   // intrările redate: fără «cameră» (nu se inventează)
                if let exif = p[kCGImagePropertyExifDictionary] as? [CFString: Any], let d = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
                    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy:MM:dd HH:mm:ss"; when = f.date(from: d)
                }
            }
            out.append((u.path, Int64(v.fileSize ?? 0), mtimeNs, cam, when))
        }
        return out.sorted { $0.path < $1.path }
    }
}
