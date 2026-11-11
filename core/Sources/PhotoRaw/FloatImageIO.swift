import Foundation
import CoreGraphics
import ImageIO
import Dispatch
import CZlib

/// Imagine RGB float32 (intercalată R,G,B), fără tăiere. Folosită pentru intermediarul către Resolve.
public struct FloatImage: Equatable {
    public var width: Int, height: Int
    public var rgb: [Float]
    public init(width: Int, height: Int, rgb: [Float]) { self.width = width; self.height = height; self.rgb = rgb }
}

public enum FloatImageError: Error { case destination, finalize, read, size }

public enum FloatImageIO {
    /// Scrie EXR float32 (ZIP, blocuri de 16 linii) cu scriitor PROPRIU: ImageIO convertește valorile prin spațiul de culoare declarat (măsurat: eroare ~8e-5 și matrice
    /// aproape-identitate chiar și cu „linear sRGB”), iar intermediarul nostru e codat DaVinci Intermediate / DWG, nu sRGB. Fără atribut de cromaticitate (ca fișierele de probă validate în Resolve).
    /// Format: OpenEXR scanline, canale B,G,R float32; compresie ZIP (reordonare octeți + predictor + zlib) cu revenire la date necomprimate dacă nu câștigă.
    public static func writeEXR(_ img: FloatImage, to url: URL) throws {
        let w = img.width, h = img.height; guard img.rgb.count == w * h * 3, w > 0, h > 0 else { throw FloatImageError.size }
        var head = Data([0x76, 0x2f, 0x31, 0x01, 2, 0, 0, 0])
        func str(_ s: String) { head.append(contentsOf: Array(s.utf8)); head.append(0) }
        func i32(_ v: Int32) { withUnsafeBytes(of: v.littleEndian) { head.append(contentsOf: $0) } }
        func attr(_ name: String, _ type: String, _ payload: Data) { str(name); str(type); i32(Int32(payload.count)); head.append(payload) }
        func le32(_ v: Int32) -> Data { var d = Data(); withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) }; return d }
        func lef(_ v: Float) -> Data { var d = Data(); withUnsafeBytes(of: v.bitPattern.littleEndian) { d.append(contentsOf: $0) }; return d }
        var ch = Data(); for n in ["B", "G", "R"] { ch.append(contentsOf: Array(n.utf8)); ch.append(0); ch.append(le32(2)); ch.append(contentsOf: [0, 0, 0, 0]); ch.append(le32(1)); ch.append(le32(1)) }; ch.append(0)
        attr("channels", "chlist", ch); attr("compression", "compression", Data([3]))
        let box = le32(0) + le32(0) + le32(Int32(w - 1)) + le32(Int32(h - 1)); attr("dataWindow", "box2i", box); attr("displayWindow", "box2i", box)
        attr("lineOrder", "lineOrder", Data([0])); attr("pixelAspectRatio", "float", lef(1)); attr("screenWindowCenter", "v2f", lef(0) + lef(0)); attr("screenWindowWidth", "float", lef(1))
        head.append(0)
        let lines = 16, nBlocks = (h + lines - 1) / lines
        var blocks = [Data](repeating: Data(), count: nBlocks)
        img.rgb.withUnsafeBufferPointer { src in
            blocks.withUnsafeMutableBufferPointer { out in
                let outBase = out.baseAddress!
                DispatchQueue.concurrentPerform(iterations: nBlocks) { b in
                    let y0 = b * lines, n = min(lines, h - y0), rawSize = n * w * 12
                    var raw = [UInt8](repeating: 0, count: rawSize)
                    raw.withUnsafeMutableBytes { rb in
                        let f = rb.bindMemory(to: UInt32.self)
                        for l in 0..<n { for (ci, c) in [2, 1, 0].enumerated() { let base = (l * 3 + ci) * w; for x in 0..<w { f[base + x] = src[3 * ((y0 + l) * w + x) + c].bitPattern.littleEndian } } }
                    }
                    var tmp = [UInt8](repeating: 0, count: rawSize); let half = (rawSize + 1) / 2
                    for i in 0..<rawSize { tmp[(i & 1 == 0) ? i / 2 : half + i / 2] = raw[i] }
                    var p = Int(tmp[0]); for i in 1..<rawSize { let d = Int(tmp[i]) - p + 384; p = Int(tmp[i]); tmp[i] = UInt8(truncatingIfNeeded: d) }
                    var cap = uLong(compressBound(uLong(rawSize))); var comp = [UInt8](repeating: 0, count: Int(cap))
                    let rc = compress2(&comp, &cap, tmp, uLong(rawSize), 6)
                    var payload: Data
                    if rc == Z_OK && Int(cap) < rawSize { payload = Data(comp[0..<Int(cap)]) } else { payload = Data(raw) }
                    var blk = Data(); withUnsafeBytes(of: Int32(y0).littleEndian) { blk.append(contentsOf: $0) }; withUnsafeBytes(of: Int32(payload.count).littleEndian) { blk.append(contentsOf: $0) }; blk.append(payload)
                    outBase[b] = blk
                }
            }
        }
        var file = head; var offset = UInt64(head.count + 8 * nBlocks)
        for b in blocks { withUnsafeBytes(of: offset.littleEndian) { file.append(contentsOf: $0) }; offset += UInt64(b.count) }
        for b in blocks { file.append(b) }
        try file.write(to: url, options: .atomic)
    }

    /// Citește un EXR (ImageIO) ca float32 RGB, FĂRĂ conversie: octeții decodați ai CGImage (float32, 4 canale) sunt copiați direct.
    public static func readEXR(_ url: URL) throws -> FloatImage {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let cg = CGImageSourceCreateImageAtIndex(src, 0, nil),
              cg.bitsPerComponent == 32, cg.bitmapInfo.contains(.floatComponents), let data = cg.dataProvider?.data else { throw FloatImageError.read }
        let w = cg.width, h = cg.height, bpp = cg.bitsPerPixel / 32, bpr = cg.bytesPerRow
        guard bpp >= 3, CFDataGetLength(data) >= bpr * h else { throw FloatImageError.read }
        let alphaFirst = [.premultipliedFirst, .first, .noneSkipFirst].contains(cg.alphaInfo); let o = (bpp == 4 && alphaFirst) ? 1 : 0
        var rgb = [Float](repeating: 0, count: w * h * 3)
        CFDataGetBytePtr(data).withMemoryRebound(to: UInt8.self, capacity: bpr * h) { base in
            for y in 0..<h { base.advanced(by: y * bpr).withMemoryRebound(to: Float.self, capacity: w * bpp) { row in
                for x in 0..<w { for c in 0..<3 { rgb[3 * (y * w + x) + c] = row[x * bpp + o + c] } } } }
        }
        return FloatImage(width: w, height: h, rgb: rgb)
    }
}
