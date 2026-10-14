import AppKit
import CoreAudio

/// Een app die bij Core Audio bekend is, met alle bijbehorende audioprocessen
/// (browsers spelen bijvoorbeeld af vanuit aparte helper-processen).
struct AudioApp: Identifiable, Hashable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
    var processObjects: [AudioObjectID]
    var isPlaying: Bool
    var isRunning: Bool

    var icon: NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    }

    /// Placeholder voor een gekozen app die nu niet draait.
    static func notRunning(bundleID: String) -> AudioApp {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        let name = url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
        return AudioApp(bundleID: bundleID, name: name ?? bundleID, processObjects: [], isPlaying: false, isRunning: false)
    }
}

enum AudioProcesses {
    private typealias ResponsibleFn = @convention(c) (pid_t) -> pid_t
    /// Geeft de "verantwoordelijke" app van een proces, zodat helpers (Chrome Helper, WebKit, …) bij hun app horen.
    private static let responsiblePID: ResponsibleFn? = {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid")
        else { return nil }
        return unsafeBitCast(sym, to: ResponsibleFn.self)
    }()

    /// Alle zichtbare apps (Dock-apps) met audioprocessen, gegroepeerd per app.
    static func apps() -> [AudioApp] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var byBundle: [String: AudioApp] = [:]

        for object in processObjects() {
            guard let pid: pid_t = property(object, kAudioProcessPropertyPID), pid != ownPID else { continue }
            let owner = responsiblePID?(pid) ?? pid
            let app = NSRunningApplication(processIdentifier: owner > 0 ? owner : pid)
            guard let app, app.activationPolicy == .regular, app.processIdentifier != ownPID,
                  let bundleID = app.bundleIdentifier else { continue }

            let playing = (property(object, kAudioProcessPropertyIsRunningOutput) as UInt32? ?? 0) != 0
            if var existing = byBundle[bundleID] {
                existing.processObjects.append(object)
                existing.isPlaying = existing.isPlaying || playing
                byBundle[bundleID] = existing
            } else {
                byBundle[bundleID] = AudioApp(bundleID: bundleID, name: app.localizedName ?? bundleID,
                                              processObjects: [object], isPlaying: playing, isRunning: true)
            }
        }
        return Array(byBundle.values)
    }

    /// Roept `handler` aan (op de main queue) zodra er audioprocessen bijkomen of verdwijnen.
    static func observeChanges(_ handler: @escaping () -> Void) {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main) { _, _ in handler() }
    }

    private static func processObjects() -> [AudioObjectID] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func property<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> T? {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, value) == noErr else { return nil }
        return value.pointee
    }
}
