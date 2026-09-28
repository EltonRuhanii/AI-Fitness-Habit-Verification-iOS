import Foundation

/// Minimal atomic JSON file persistence in `Application Support/Demo/`. Used only by demo-mode
/// services; production data goes through Firestore and its offline cache.
struct LocalJSONStore<Value: Codable> {
    let url: URL

    init(fileName: String, fileManager: FileManager = .default) {
        let base = (try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fileManager.temporaryDirectory
        let directory = base.appendingPathComponent("Demo", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        self.url = directory.appendingPathComponent(fileName)
    }

    func load() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.iso8601.decode(Value.self, from: data)
    }

    func save(_ value: Value) throws {
        let data = try JSONEncoder.iso8601.encode(value)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    static func removeAllDemoData(fileManager: FileManager = .default) {
        guard let base = try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false) else { return }
        try? fileManager.removeItem(at: base.appendingPathComponent("Demo", isDirectory: true))
    }
}

extension JSONEncoder {
    static let iso8601: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension JSONDecoder {
    static let iso8601: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
