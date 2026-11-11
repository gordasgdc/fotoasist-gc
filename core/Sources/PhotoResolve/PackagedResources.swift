import Foundation
import PhotoCore

/// Inventarul resurselor care trebuie să existe în aplicația împachetată. Lipsa uneia = eroare EXPLICITĂ (jurnal + mesaj în modulul afectat), niciodată oprirea procesului sau o rezervă tăcută care schimbă rezultatul.
public enum PackagedResources {
    public struct Item: Equatable { public let name: String; public let module: String; public let found: Bool }
    static func find(_ name: String, _ ext: String, _ sub: String?) -> Bool {
        (Bundle.main.url(forResource: name, withExtension: ext, subdirectory: sub) ?? ModuleBundle.optional?.url(forResource: name, withExtension: ext, subdirectory: sub)) != nil
    }
    public static func audit() -> [Item] {
        (Edition.full ? [Item(name: "film_models.gdcfilm", module: "Stiluri cinema", found: find("film_models", "gdcfilm", "film"))] : []) +
        [Item(name: "colorchecker_classic.json", module: L("Chart de culoare"), found: find("colorchecker_classic", "json", "charts")),
         Item(name: "FotoAsist-GC_simbol.svg", module: "Marcă (antet)", found: find("FotoAsist-GC_simbol", "svg", "Brand") || find("FotoAsist-GC_simbol", "svg", nil))]
    }
    public static var missing: [Item] { audit().filter { !$0.found } }
}
