import SwiftUI
import AppKit
import Security
import PhotoCore
import PhotoAccess
import PhotoResolve

/// Starea semnăturii aplicației, VERIFICATĂ la rulare (nu dedusă din numele versiunii): Developer ID al echipei GDC, ad-hoc (build local) sau neverificabilă.
public enum CodeSignatureStatus: Equatable, Sendable { case developerID(team: String), adHoc, unverified }

public extension AppInfo {
    static let teamID = "8AR6XP8MG7"
    static func verifyCodeSignature(bundleURL: URL = Bundle.main.bundleURL, team: String = AppInfo.teamID) -> CodeSignatureStatus {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &code) == errSecSuccess, let code else { return .unverified }
        var req: SecRequirement?
        let text = "anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"\(team)\""
        if SecRequirementCreateWithString(text as CFString, [], &req) == errSecSuccess, let req,
           SecStaticCodeCheckValidityWithErrors(code, [], req, nil) == errSecSuccess { return .developerID(team: team) }
        guard SecStaticCodeCheckValidityWithErrors(code, [], nil, nil) == errSecSuccess else { return .unverified }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let d = info as? [String: Any], let flags = d[kSecCodeInfoFlags as String] as? UInt32 else { return .unverified }
        return flags & 0x2 != 0 ? .adHoc : .unverified   // 0x2 = kSecCodeSignatureAdhoc
    }
    /// Text de copiat (versiune + build), din metadatele aplicației.
    static var identityLine: String { "FotoAsist GC \(version) (build \(build))" }
}

@MainActor public final class UpdateController: ObservableObject {
    public static let shared = UpdateController()
    public enum State: Equatable { case idle, checking, done(PhotoUpdateResult) }
    @Published public private(set) var state: State = .idle
    var checker: PhotoUpdateChecker
    public init(checker: PhotoUpdateChecker = PhotoUpdateChecker()) { self.checker = checker }
    public func check() async {
        if state == .checking { return }
        state = .checking
        state = .done(await checker.check(installedVersion: AppInfo.version))
    }
    public func openDownload(_ o: PhotoUpdateOffer) { NSWorkspace.shared.open(o.downloadURL) }
}

/// Versiune, build și semnătură verificată — text selectabil, cu copiere.
struct BuildIdentityView: View {
    var session: String? = nil
    @State private var sig: CodeSignatureStatus?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                Text(LF("Versiune %@", AppInfo.version)).font(Theme.f(14, weight: .semibold))
                Text(LF("Build %@", AppInfo.build)).font(Theme.f(12)).foregroundColor(Theme.muted)
                if let session { Text(LF("Sesiune %@", session)).font(Theme.f(12)).foregroundColor(Theme.muted) }
                if let sig { Text(Self.text(sig)).font(Theme.f(12)).foregroundColor(Theme.muted) }
            }.textSelection(.enabled)
            if ManualLibrary.anyEditionAvailable() { Button(L("Manual de utilizare…")) { ManualLibrary.open() }.buttonStyle(SoftButtonStyle()).help(L("Se deschide offline, în limba aplicației; alege altă ediție din meniul Ajutor")) }
            Button(L("Copiază informațiile versiunii")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(AppInfo.identityLine, forType: .string) }.buttonStyle(SoftButtonStyle()).padding(.top, 4)
        }.task { sig = await Task.detached { AppInfo.verifyCodeSignature() }.value }
    }
    static func text(_ s: CodeSignatureStatus) -> String {
        switch s {
        case .developerID(let t): return LF("Semnătură verificată: Developer ID, echipa %@", t)
        case .adHoc: return L("Build local: semnătură ad-hoc (doar pentru verificare locală)")
        case .unverified: return L("Semnătura aplicației nu a putut fi verificată")
        }
    }
}

struct UpdateSection: View {
    @ObservedObject var updater = UpdateController.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LF("Versiunea instalată: %@", AppInfo.version)).font(Theme.f(12.5))
            switch updater.state {
            case .idle: EmptyView()
            case .checking: HStack(spacing: 6) { ProgressView().controlSize(.small); Text(L("Verific…")).font(Theme.f(12.5)).foregroundColor(Theme.muted) }
            case .done(let r): result(r)
            }
            if case .done(.updateAvailable(let o)) = updater.state {
                Button(LF("Descarcă instalatorul %@", o.version)) { updater.openDownload(o) }.buttonStyle(PrimaryButtonStyle())
            }
            Button(L("Verifică actualizările…")) { Task { await updater.check() } }.buttonStyle(SoftButtonStyle()).disabled(updater.state == .checking)
        }.textSelection(.enabled)
    }
    @ViewBuilder func result(_ r: PhotoUpdateResult) -> some View {
        switch r {
        case .upToDate(_, let a): Text(LF("Ești la zi: ai cea mai nouă versiune (%@).", a)).font(Theme.f(12.5)).foregroundColor(Theme.keep)
        case .updateAvailable(let o):
            Text(LF("Versiunea disponibilă: %@", o.version)).font(Theme.f(12.5, weight: .semibold))
            Text(L("Închide aplicația și DaVinci Resolve, apoi instalează peste versiunea existentă. Nimic nu se instalează automat.")).font(Theme.f(11.5)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
            if let n = o.notes[Localizer.shared.resolved.rawValue] ?? o.notes["ro"] { Text(n).font(Theme.f(11.5)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true) }
        case .offline: Text(L("Nu pot verifica acum: nu există conexiune la internet. Aplicația funcționează normal; încearcă din nou mai târziu.")).font(Theme.f(12.5)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
        case .invalid(let c): Text(LF("Manifestul de actualizare nu a putut fi acceptat (%@). Nu s-a oferit nicio actualizare.", c)).font(Theme.f(12.5)).foregroundColor(Theme.reject).fixedSize(horizontal: false, vertical: true)
        case .failed(let d): Text(LF("Verificarea a eșuat (%@). Încearcă din nou mai târziu.", d)).font(Theme.f(12.5)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Ediția cu sursă deschisă: licența, autorul și locul unde se află sursa (afișate în «Despre»).
struct OpenEditionNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LF("Ediție cu sursă deschisă · %@", Edition.license)).font(Theme.f(12.5, weight: .semibold))
            Text(L("Gratuit, fără cont, activare, perioadă de probă sau server de licențiere. Proiect deschis contribuțiilor, cu mentenanță ocazională.")).font(Theme.f(11.5)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
            Text(L("Mențiunile pentru componentele terțe sunt în THIRD_PARTY_NOTICES.md, în sursă și în pachet.")).font(Theme.f(11.5)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
            Button(L("Deschide pagina proiectului (sursă, Issues, Pull Requests)")) { NSWorkspace.shared.open(Edition.sourceURL) }.buttonStyle(SoftButtonStyle()).padding(.top, 2)
        }.textSelection(.enabled)
    }
}

/// Fereastra „Despre FotoAsist GC” din meniul aplicației (independentă de bibliotecă: se deschide și în ecranele de configurare).
public struct AppAboutView: View {
    @ObservedObject private var loc = Localizer.shared
    public init() {}
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) { BrandSymbol(size: 40, tint: Theme.text)
                VStack(alignment: .leading, spacing: 2) { Text("FotoAsist GC").font(Theme.f(20, weight: .semibold)); Text(Edition.full ? "GDC" : Edition.author).font(Theme.f(12)).foregroundColor(Theme.muted) } }
            BuildIdentityView()
            if !Edition.full { OpenEditionNotice() }
            Divider().overlay(Theme.line)
            UpdateSection()
        }.padding(24).frame(width: 460, alignment: .leading).background(Theme.app).foregroundColor(Theme.text).preferredColorScheme(.dark).id(loc.resolved.rawValue)
    }
}
