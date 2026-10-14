import Foundation

struct AirPlayOutput: Identifiable, Decodable, Hashable {
    let id: String
    let name: String
    let type: String
    var selected: Bool
    var volume: Int
}

/// Start/stopt de meegeleverde OwnTone-server en praat met zijn JSON API op localhost:3689.
/// OwnTone verzorgt de gesynchroniseerde AirPlay 2-multiroomstreaming.
///
/// De binary, libraries en config-template zitten in `Wallastream.app/Contents/Resources/owntone`;
/// database, log en audiopipe komen in `~/Library/Application Support/Wallastream`.
final class OwnTone {
    let bundleDir: URL
    let dataDir: URL
    var pipePath: String { dataDir.appendingPathComponent("media/Mac-audio").path }
    var logURL: URL { dataDir.appendingPathComponent("log/owntone.log") }

    private var process: Process?
    private let base = URL(string: "http://127.0.0.1:3689/api/")!

    init(bundleDir: URL, dataDir: URL) {
        self.bundleDir = bundleDir
        self.dataDir = dataDir
    }

    func launch() async throws {
        if await isReachable() { return } // draait al (bijv. van een vorige sessie)

        let config = try prepareDataDir()
        let p = Process()
        p.executableURL = bundleDir.appendingPathComponent("owntone")
        p.arguments = ["-f", "-c", config.path,
                       "-s", bundleDir.appendingPathComponent("owntone-sqlext.so").path,
                       "-w", dataDir.appendingPathComponent("web").path,
                       // Niet als muziekbibliotheek op het netwerk adverteren.
                       "--mdns-no-rsp", "--mdns-no-daap", "--mdns-no-cname", "--mdns-no-web"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        process = p

        for _ in 0..<40 {
            if await isReachable() { return }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw NSError(domain: "Wallastream", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "OwnTone start niet. Zie \(logURL.path)"])
    }

    /// Maakt de mappen en de named pipe aan en schrijft owntone.conf vanuit het template.
    private func prepareDataDir() throws -> URL {
        let fm = FileManager.default
        for sub in ["media", "log", "cache", "web"] {
            try fm.createDirectory(at: dataDir.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        if mkfifo(pipePath, 0o644) != 0 && errno != EEXIST {
            throw NSError(domain: "Wallastream", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Kan pipe niet aanmaken op \(pipePath)"])
        }
        let template = try String(contentsOf: bundleDir.appendingPathComponent("owntone.conf.template"), encoding: .utf8)
        let config = template
            .replacingOccurrences(of: "@DATA@", with: dataDir.path)
            .replacingOccurrences(of: "@USER@", with: NSUserName())
        let url = dataDir.appendingPathComponent("owntone.conf")
        try config.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func terminate() {
        guard let process, process.isRunning else { return }
        process.terminate()
        process.waitUntilExit()
    }

    /// Laatste logregel over dit apparaat, om te zien waarom het niet wil afspelen.
    func lastLogLine(mentioning deviceName: String) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: logURL) else { return nil }
        defer { try? handle.close() }
        let end = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: end > 65_536 ? end - 65_536 : 0)
        guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) else { return nil }
        return text.split(separator: "\n").last { $0.contains("'\(deviceName)'") }.map(String.init)
    }

    // MARK: API

    func outputs() async throws -> [AirPlayOutput] {
        struct Response: Decodable { let outputs: [AirPlayOutput] }
        let (data, _) = try await URLSession.shared.data(from: base.appendingPathComponent("outputs"))
        return try JSONDecoder().decode(Response.self, from: data).outputs
    }

    func setSelectedOutputs(_ ids: [String]) async throws {
        try await send("PUT", "outputs/set", body: ["outputs": ids])
    }

    /// Wachtwoord of PIN voor een beveiligd AirPlay-apparaat. OwnTone koppelt en bewaart de sleutel zelf.
    func authorize(output id: String, pin: String) async throws {
        try await send("PUT", "outputs/\(id)", body: ["pin": pin])
    }

    func setVolume(_ volume: Int, output id: String) async throws {
        try await send("PUT", "outputs/\(id)", body: ["volume": volume])
    }

    func playPipe() async throws {
        struct Search: Decodable {
            struct Tracks: Decodable { let items: [Item] }
            struct Item: Decodable { let uri: String; let title: String }
            let tracks: Tracks
        }
        var comps = URLComponents(url: base.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [.init(name: "type", value: "tracks"),
                            .init(name: "expression", value: "data_kind is pipe")]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        guard let uri = try JSONDecoder().decode(Search.self, from: data).tracks.items.first?.uri else {
            throw NSError(domain: "Wallastream", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Audiopipe niet gevonden in OwnTone-bibliotheek"])
        }
        try await send("POST", "queue/items/add?uris=\(uri)&clear=true&playback=start")
    }

    func stopPlayback() async throws {
        try await send("PUT", "player/stop")
    }

    private func isReachable() async -> Bool {
        var req = URLRequest(url: base.appendingPathComponent("config"))
        req.timeoutInterval = 1
        return (try? await URLSession.shared.data(for: req)) != nil
    }

    private func send(_ method: String, _ path: String, body: [String: Any]? = nil) async throws {
        var req = URLRequest(url: URL(string: path, relativeTo: base)!)
        req.httpMethod = method
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (_, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError(domain: "Wallastream", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "OwnTone \(method) \(path) gaf HTTP \(http.statusCode)"])
        }
    }
}
