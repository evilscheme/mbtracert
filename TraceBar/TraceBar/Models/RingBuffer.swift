struct RingBuffer<T> {
    private var storage: [T?]
    private var writeIndex = 0
    private(set) var count = 0

    let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
        self.storage = Array(repeating: nil, count: capacity)
    }

    init(from elements: [T], capacity: Int) {
        self.init(capacity: capacity)
        for element in elements {
            append(element)
        }
    }

    mutating func append(_ element: T) {
        storage[writeIndex] = element
        writeIndex = (writeIndex + 1) % capacity
        count = min(count + 1, capacity)
    }

    var last: T? {
        guard count > 0 else { return nil }
        let idx = (writeIndex - 1 + capacity) % capacity
        return storage[idx]
    }

    var elements: [T] {
        if count < capacity {
            return storage[0..<count].compactMap { $0 }
        }
        let tail = storage[writeIndex..<capacity].compactMap { $0 }
        let head = storage[0..<writeIndex].compactMap { $0 }
        return tail + head
    }

    /// Iterate over elements in chronological order without allocating an array.
    func forEach(_ body: (T) -> Void) {
        if count < capacity {
            for i in 0..<count {
                if let el = storage[i] { body(el) }
            }
        } else {
            for i in writeIndex..<capacity {
                if let el = storage[i] { body(el) }
            }
            for i in 0..<writeIndex {
                if let el = storage[i] { body(el) }
            }
        }
    }
}
