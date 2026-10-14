import AppKit
import SwiftUI

@main
struct WallastreamApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: delegate.model)
        } label: {
            Image(systemName: delegate.model.isStreaming ? "hifispeaker.2.fill" : "hifispeaker.2")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor let model = AppModel()

    @MainActor func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
    }
}

struct MenuView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wallastream").font(.headline)
                    Text(model.status).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(get: { model.isStreaming }, set: { model.setStreaming($0) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            Divider()

            if model.outputs.isEmpty {
                Text("Zoeken naar AirPlay-speakers…")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(model.outputs) { output in
                    OutputRow(model: model, output: output)
                }
            }

            Divider()

            Text("Bron").font(.caption).foregroundStyle(.secondary)
            Picker("", selection: $model.sourceMode) {
                Text("Alle geluid").tag(SourceMode.allAudio)
                Text("Gekozen apps").tag(SourceMode.selectedApps)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if model.sourceMode == .selectedApps {
                if model.audioApps.isEmpty {
                    Text("Geen apps met audio gevonden. Start iets in je browser.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(model.audioApps) { app in
                        AppRow(model: model, app: app)
                    }
                }
                Text("Andere apps en meldingen blijven op de Mac spelen.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Divider()

            Toggle(model.sourceMode == .selectedApps ? "Gekozen apps niet op de Mac afspelen"
                                                     : "Mac-speakers dempen tijdens streamen",
                   isOn: $model.muteLocal)
                .font(.callout)

            if let error = model.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Stoppen") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}

struct AppRow: View {
    let model: AppModel
    let app: AudioApp

    var body: some View {
        Toggle(isOn: Binding(get: { model.selectedApps.contains(app.bundleID) },
                             set: { _ in model.toggleApp(app) })) {
            HStack(spacing: 6) {
                Image(nsImage: app.icon).resizable().frame(width: 16, height: 16)
                Text(app.name).foregroundStyle(app.isRunning ? .primary : .secondary)
                if app.isPlaying {
                    Image(systemName: "waveform").font(.caption2).foregroundStyle(.green)
                }
            }
        }
        .toggleStyle(.checkbox)
    }
}

struct OutputRow: View {
    let model: AppModel
    let output: AirPlayOutput

    var body: some View {
        let chosen = model.chosenIDs.contains(output.id)
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(get: { chosen }, set: { _ in model.toggle(output) })) {
                Text(output.name)
            }
            .toggleStyle(.checkbox)

            if let problem = model.failedOutputs[output.id] {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(problem.message).fixedSize(horizontal: false, vertical: true)
                        if problem.needsPassword {
                            HStack(spacing: 4) {
                                SecureField("Wachtwoord of PIN",
                                            text: Binding(get: { model.passwordInput[output.id] ?? "" },
                                                          set: { model.passwordInput[output.id] = $0 }))
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit { model.authorize(output) }
                                Button("Verbinden") { model.authorize(output) }
                                    .disabled((model.passwordInput[output.id] ?? "").isEmpty)
                            }
                        }
                        Button("Opnieuw proberen") { model.retry(output) }
                            .buttonStyle(.link)
                    }
                }
                .font(.caption)
                .padding(.leading, 20)
            }

            if chosen {
                HStack(spacing: 6) {
                    Image(systemName: "speaker.fill").font(.caption2).foregroundStyle(.secondary)
                    Slider(value: Binding(get: { Double(output.volume) },
                                          set: { model.previewVolume($0, for: output) }),
                           in: 0...100) { isEditing in
                        model.editingVolumeID = isEditing ? output.id : nil
                        if !isEditing { model.commitVolume(for: output) }
                    }
                    .controlSize(.small)
                    Image(systemName: "speaker.wave.3.fill").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.leading, 20)
            }
        }
    }
}
