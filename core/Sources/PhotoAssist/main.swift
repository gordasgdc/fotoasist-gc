import SwiftUI
import AppKit
import PhotoAssistUI
import PhotoCore

// Aplicația FotoAsist GC (versiune de dezvoltare; slug tehnic neschimbat: gdc-photo-assist). Biblioteca/jurnalele: vezi AppBootstrap (extern în build-ul de dezvoltare; GDC_PA_LIBRARY în teste).
@main struct PhotoAssistApp: App {
    @StateObject private var host = MainActor.assumeIsolated { AppHost() }
    var body: some Scene {
        WindowGroup("FotoAsist GC") {
            switch host.state {
            case .ready(let model): RootView(model: model, host: host).frame(minWidth: 1180, minHeight: 720)
            case .needsSetup: FirstRunStorageView(host: host).frame(minWidth: 900, minHeight: 600)
            case .unavailable(let h, let loc): StorageUnavailableView(host: host, health: h, location: loc).frame(minWidth: 900, minHeight: 600)
            case .failed(let d): StorageMissingView(detail: d).frame(minWidth: 900, minHeight: 600)
            }
        }.windowStyle(.titleBar).commands { AdjustmentCommands(host: host) }
        Window(L("Despre FotoAsist GC"), id: "about") { AppAboutView() }.windowResizability(.contentSize)
    }
}
