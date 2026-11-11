import Foundation

/// Pachetul de resurse SwiftPM NU există în aplicația împachetată (resursele stau în Contents/Resources și se caută prin Bundle.main); accesarea `Bundle.module` acolo oprește procesul. Se folosește doar la rularea din SwiftPM/teste.
enum ModuleBundle { static var optional: Bundle? { Bundle.main.bundleURL.pathExtension == "app" ? nil : Bundle.module } }
