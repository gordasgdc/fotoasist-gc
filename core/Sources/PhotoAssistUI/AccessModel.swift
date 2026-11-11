import SwiftUI
import AppKit
import PhotoAccess
import PhotoCore
import PhotoResolve

/// Open-source edition: there is no licence state to evaluate. The model only carries the feature policy
/// (which permits everything) so the rest of the interface keeps a single place to ask.
@MainActor
public final class AccessModel: ObservableObject {
    public let policy: PhotoFeaturePolicy
    public init(policy: PhotoFeaturePolicy = PhotoPolicies.standard()) {
        self.policy = policy
        DiagnosticLog.shared?.log(.info, "access", "state", "open-source edition · \(policy.name)")
    }
    public func permits(_ f: PhotoFeature) -> Bool { policy.permits(f) }
    public var chipText: String { L("Sursă deschisă") }
}

/// Header chip: says which edition this is and where the source lives.
struct AccessChip: View {
    @ObservedObject var access: AccessModel; var compact = false; @State private var open = false
    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 5) { Circle().fill(Theme.keep).frame(width: 7, height: 7); Text(access.chipText).font(Theme.f(11.5)).lineLimit(1).fixedSize() }.fixedSize()
        }.buttonStyle(SoftButtonStyle()).help(L("Ediție cu sursă deschisă")).accessibilityLabel(L("Ediție cu sursă deschisă"))
            .sheet(isPresented: $open) { AccessSheet() }
    }
}

struct AccessSheet: View {
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(L("Ediție cu sursă deschisă")).font(Theme.f(18, weight: .semibold)); Spacer(); Button(L("Închide")) { dismiss() }.buttonStyle(SoftButtonStyle()) }
            Text(L("FotoAsist GC este gratuit și cu sursă deschisă. Nu are cont, activare, perioadă de probă sau server de licențiere: toate funcțiile acestei ediții sunt disponibile fără restricții.")).font(Theme.f(12.5)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
            Text(LF("Licență: %@", Edition.license)).font(Theme.f(12.5))
            Text(LF("Autor: %@", Edition.author)).font(Theme.f(12.5))
            OpenEditionNotice()
        }.padding(20).frame(minWidth: 480, idealWidth: 560, maxWidth: 680, alignment: .leading).background(Theme.app).foregroundColor(Theme.text)
    }
}
