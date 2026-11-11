import Foundation

/// Ediția produsului, fixată la compilare.
///  • ediția completă GDC: toate modulele (GDC DRT, Color/Skin selectiv, Optics, Film V3, Look, Cinema Style);
///  • ediția cu sursă deschisă (`GDC_PA_OPEN_EDITION`, GPL-3.0-or-later): aceleași instrumente de bază, fără modulele de mai sus și fără licențiere.
/// Valorile salvate ale modulelor absente se păstrează în fișiere (nu se pierd la schimbarea ediției), dar nu au efect.
public enum Edition {
    #if GDC_PA_OPEN_EDITION
    public static let full = false
    #else
    public static let full = true
    #endif
    /// Depozitul public al ediției cu sursă deschisă (cod, Issues, Pull Requests).
    public static let sourceURL = URL(string: "https://github.com/gordasgdc/fotoasist-gc")!
    public static let author = "Dumitru Cristinel Gordas (GDC)"
    public static let license = "GPL-3.0-or-later"
}
