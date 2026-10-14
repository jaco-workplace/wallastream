import CoreAudio
import Foundation
import Observation

struct OutputProblem: Equatable {
    let message: String
    let needsPassword: Bool
}

enum SourceMode: String {
    case allAudio, selectedApps
}

@MainActor
@Observable
final class AppModel {
    var outputs: [AirPlayOutput] = []
    var chosenIDs: Set<String> {
        didSet { UserDefaults.standard.set(Array(chosenIDs), forKey: "chosenIDs") }
    }
    var muteLocal: Bool {
        didSet {
            UserDefaults.standard.set(muteLocal, forKey: "muteLocal")
            if isStreaming { restartCapture() }
        }
    }
    var sourceMode: SourceMode {
        didSet {
            UserDefaults.standard.set(sourceMode.rawValue, forKey: "sourceMode")
            if isStreaming { restartCapture() }
        }
    }
    var selectedApps: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(selectedApps), forKey: "selectedApps")
            refreshApps()
        }
    }
    /// Apps die audio gebruiken, plus gekozen apps die nu niet draaien.
    var audioApps: [AudioApp] = []
    var isStreaming = false
    /// Gekozen speakers die niet willen afspelen, met de reden (output-id → melding).
    var failedOutputs: [String: OutputProblem] = [:]
    /// Wat er in het wachtwoordveld van een speaker is getypt (alleen in het geheugen).
    var passwordInput: [String: String] = [:]
    /// Wanneer we een speaker hebben aangezet; OwnTone krijgt even de tijd om te verbinden.
    private var requestedAt: [String: Date] = [:]
    var editingVolumeID: String?
    var status = "OwnTone starten…"
    var errorMessage: String?

    private let owntone: OwnTone
    private let capture = SystemAudioCapture()
    private var writer: PipeWriter?
    private var pollTask: Task<Void, Never>?

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        owntone = OwnTone(bundleDir: Bundle.main.resourceURL!.appendingPathComponent("owntone"),
                          dataDir: support.appendingPathComponent("Wallastream"))
        chosenIDs = Set(UserDefaults.standard.stringArray(forKey: "chosenIDs") ?? [])
        muteLocal = UserDefaults.standard.object(forKey: "muteLocal") as? Bool ?? true
        sourceMode = SourceMode(rawValue: UserDefaults.standard.string(forKey: "sourceMode") ?? "") ?? .allAudio
        selectedApps = Set(UserDefaults.standard.stringArray(forKey: "selectedApps") ?? [])

        refreshApps()
        AudioProcesses.observeChanges { [weak self] in
            MainActor.assumeIsolated { self?.refreshApps() }
        }
        AudioProcesses.observeDefaultOutput { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isStreaming else { return }
                self.restartCapture()
            }
        }

        Task { await boot() }
    }

    private func boot() async {
        do {
            try await owntone.launch()
            status = "Klaar"
            pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.refreshOutputs()
                    self?.refreshApps()
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        } catch {
            status = "OwnTone niet beschikbaar"
            errorMessage = error.localizedDescription
        }
    }

    func refreshOutputs() async {
        guard editingVolumeID == nil, let list = try? await owntone.outputs() else { return }
        outputs = list
            .filter { $0.type.hasPrefix("AirPlay") }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        checkFailedOutputs()
    }

    /// Een gekozen speaker die een paar seconden na het aanzetten nog niet "selected" is in OwnTone,
    /// is geweigerd of onbereikbaar. OwnTone zet zulke apparaten zelf weer uit.
    private func checkFailedOutputs() {
        guard isStreaming else { failedOutputs = [:]; return }
        for output in outputs where chosenIDs.contains(output.id) {
            if output.selected {
                failedOutputs[output.id] = nil
            } else if failedOutputs[output.id] == nil,
                      let since = requestedAt[output.id], Date().timeIntervalSince(since) > 5 {
                failedOutputs[output.id] = reason(for: output)
            }
        }
    }

    private func reason(for output: AirPlayOutput) -> OutputProblem {
        let line = owntone.lastLogLine(mentioning: output.name) ?? ""
        let isMac = output.name.hasPrefix("Mac") || output.name.contains("MacBook") || output.name.contains("iMac")
        if line.contains("PIN") || line.contains("password") || line.contains("403") {
            let message = isMac
                ? "Geweigerd. Op die Mac: Systeeminstellingen → AirDrop en Handoff → AirPlay-ontvanger → \"Iedereen in hetzelfde netwerk\". Staat er een wachtwoord op, vul dat hieronder in."
                : "Dit apparaat vraagt om een wachtwoord of PIN (soms staat de PIN op het scherm van het apparaat)."
            return OutputProblem(message: message, needsPassword: true)
        }
        if line.contains("closed RTSP") || line.contains("failed during") {
            return OutputProblem(message: "Verbinding verbroken. Speelt iemand anders er nu op af? Met \"Opnieuw proberen\" neem je hem weer over.",
                                 needsPassword: false)
        }
        return OutputProblem(message: "Speelt niet af: kon geen verbinding maken.", needsPassword: false)
    }

    func authorize(_ output: AirPlayOutput) {
        let pin = (passwordInput[output.id] ?? "").trimmingCharacters(in: .whitespaces)
        guard !pin.isEmpty else { return }
        passwordInput[output.id] = nil
        failedOutputs[output.id] = nil
        requestedAt[output.id] = Date()
        Task {
            await apply {
                try await self.owntone.authorize(output: output.id, pin: pin)
                try await Task.sleep(for: .seconds(1))
                try await self.owntone.setSelectedOutputs(self.activeIDs)
            }
        }
    }

    /// Opnieuw proberen na een melding (bijv. nadat de instelling op die Mac is aangepast).
    func retry(_ output: AirPlayOutput) {
        failedOutputs[output.id] = nil
        requestedAt[output.id] = Date()
        Task { await apply { try await self.owntone.setSelectedOutputs(self.activeIDs) } }
    }

    func refreshApps() {
        let running = AudioProcesses.apps()
        let runningIDs = Set(running.map(\.bundleID))
        let missing = selectedApps.subtracting(runningIDs).map(AudioApp.notRunning)
        audioApps = (running + missing)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        // Nieuwe helper-processen (bijv. een browsertab die gaat afspelen) direct meenemen.
        if isStreaming, sourceMode == .selectedApps {
            capture.updateProcesses(tappedProcesses)
        }
    }

    func toggleApp(_ app: AudioApp) {
        if selectedApps.contains(app.bundleID) { selectedApps.remove(app.bundleID) } else { selectedApps.insert(app.bundleID) }
    }

    private var tappedProcesses: [AudioObjectID] {
        audioApps.filter { selectedApps.contains($0.bundleID) }.flatMap(\.processObjects)
    }

    func toggle(_ output: AirPlayOutput) {
        if chosenIDs.contains(output.id) {
            chosenIDs.remove(output.id)
            failedOutputs[output.id] = nil
        } else {
            chosenIDs.insert(output.id)
            requestedAt[output.id] = Date()
        }
        guard isStreaming else { return }
        Task { await apply { try await self.owntone.setSelectedOutputs(self.activeIDs) } }
    }

    /// Slider wordt versleept: alleen lokaal bijwerken.
    func previewVolume(_ volume: Double, for output: AirPlayOutput) {
        if let i = outputs.firstIndex(where: { $0.id == output.id }) { outputs[i].volume = Int(volume) }
    }

    /// Slider losgelaten: naar OwnTone sturen.
    func commitVolume(for output: AirPlayOutput) {
        guard let volume = outputs.first(where: { $0.id == output.id })?.volume else { return }
        Task { await apply { try await self.owntone.setVolume(volume, output: output.id) } }
    }

    func setStreaming(_ on: Bool) {
        Task { on ? await start() : await stop() }
    }

    /// Alleen apparaten die nu ook echt zichtbaar zijn op het netwerk.
    private var activeIDs: [String] {
        outputs.map(\.id).filter(chosenIDs.contains)
    }

    private func start() async {
        guard !activeIDs.isEmpty else {
            errorMessage = "Kies eerst minstens één speaker."
            return
        }
        guard sourceMode == .allAudio || !selectedApps.isEmpty else {
            errorMessage = "Kies eerst minstens één app."
            return
        }
        errorMessage = nil
        do {
            failedOutputs = [:]
            for id in activeIDs { requestedAt[id] = Date() }
            try await owntone.setSelectedOutputs(activeIDs)
            try startCapture()
            try await owntone.playPipe()
            isStreaming = true
            status = "Streamt naar \(activeIDs.count) speaker\(activeIDs.count == 1 ? "" : "s")"
        } catch {
            stopCapture()
            isStreaming = false
            errorMessage = error.localizedDescription
        }
    }

    private func stop() async {
        stopCapture()
        try? await owntone.stopPlayback()
        try? await owntone.setSelectedOutputs([])
        isStreaming = false
        failedOutputs = [:]
        status = "Klaar"
    }

    private func startCapture() throws {
        try capture.start(processes: sourceMode == .selectedApps ? tappedProcesses : nil, muteLocal: muteLocal)
        let w = PipeWriter(ring: capture.ring, pipePath: owntone.pipePath, inputRate: capture.sampleRate)
        w.start()
        writer = w
    }

    private func stopCapture() {
        writer?.stop()
        writer = nil
        capture.stop()
    }

    private func restartCapture() {
        stopCapture()
        do { try startCapture() } catch { errorMessage = error.localizedDescription }
    }

    private func apply(_ op: @escaping () async throws -> Void) async {
        do { try await op(); await refreshOutputs() } catch { errorMessage = error.localizedDescription }
    }

    func shutdown() {
        pollTask?.cancel()
        stopCapture()
        owntone.terminate()
    }
}
