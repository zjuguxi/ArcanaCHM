import Foundation

final class ScrollPositionStore {
    private var positions: [String: Double] = [:]
    private let lock = NSLock()
    private var workItem: DispatchWorkItem?
    private let queue = DispatchQueue(label: "arcana.scrollposition.save", qos: .utility)

    private var storeURL: URL {
        AppPaths.appSupport.appendingPathComponent("scroll_positions.json")
    }

    func load() {
        guard FileManager.default.fileExists(atPath: storeURL.path),
              let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([String: Double].self, from: data)
        else { return }
        lock.lock()
        positions = decoded
        lock.unlock()
    }

    func scrollY(bookID: UUID, path: String?) -> Double {
        guard let path else { return 0 }
        lock.lock()
        let y = positions[key(bookID: bookID, path: path)] ?? 0
        lock.unlock()
        return y
    }

    func save(bookID: UUID, path: String, scrollY: Double) {
        lock.lock()
        positions[key(bookID: bookID, path: path)] = scrollY
        lock.unlock()
        debounceWrite()
    }

    private func key(bookID: UUID, path: String) -> String {
        "\(bookID.uuidString)/\(path)"
    }

    private func debounceWrite() {
        workItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.writeToDisk()
        }
        workItem = item
        queue.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    private func writeToDisk() {
        let dict: [String: Double]
        lock.lock()
        dict = positions
        lock.unlock()
        guard let data = try? JSONEncoder().encode(dict) else { return }
        try? data.write(to: storeURL, options: [.atomic])
    }
}
