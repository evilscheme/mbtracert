struct RingBuffer<T> {
    private var storage: [T?]
    private var writeIndex = 0
    private(set) var count = 0

    let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
        self.storage = Array(repeating: nil, count: capacity)
    }

    mutating func append(_ element: T) {
        storage[writeIndex] = element
        writeIndex = (writeIndex + 1) % capacity
        count = min(count + 1, capacity)
    }

    var elements: [T] {
        if count < capacity {
            return storage[0..<count].compactMap { $0 }
        }
        let tail = storage[writeIndex..<capacity].compactMap { $0 }
        let head = storage[0..<writeIndex].compactMap { $0 }
        return tail + head
    }

    mutating func clear() {
        storage = Array(repeating: nil, count: capacity)
        writeIndex = 0
        count = 0
    }
}
