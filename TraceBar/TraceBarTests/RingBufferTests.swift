import Testing
@testable import TraceBar

@Suite("RingBuffer")
struct RingBufferTests {

    @Test func emptyBuffer() {
        let buf = RingBuffer<Int>(capacity: 5)
        #expect(buf.count == 0)
        #expect(buf.elements.isEmpty)
    }

    @Test func appendWithinCapacity() {
        var buf = RingBuffer<Int>(capacity: 5)
        buf.append(1)
        buf.append(2)
        buf.append(3)
        #expect(buf.count == 3)
        #expect(buf.elements == [1, 2, 3])
    }

    @Test func appendFillsExactly() {
        var buf = RingBuffer<Int>(capacity: 3)
        buf.append(10)
        buf.append(20)
        buf.append(30)
        #expect(buf.count == 3)
        #expect(buf.elements == [10, 20, 30])
    }

    @Test func wraparoundOverwritesOldest() {
        var buf = RingBuffer<Int>(capacity: 3)
        buf.append(1)
        buf.append(2)
        buf.append(3)
        buf.append(4) // overwrites 1
        #expect(buf.count == 3)
        #expect(buf.elements == [2, 3, 4])
    }

    @Test func wraparoundMultipleOverflows() {
        var buf = RingBuffer<Int>(capacity: 3)
        for i in 1...7 {
            buf.append(i)
        }
        #expect(buf.count == 3)
        #expect(buf.elements == [5, 6, 7])
    }

    @Test func elementsOrderIsChronological() {
        var buf = RingBuffer<Int>(capacity: 4)
        for i in 1...6 {
            buf.append(i)
        }
        // After 6 appends into capacity 4: [5,6,_,_] writeIndex=2, storage=[5,6,3,4]
        // Actually: storage = [5,6,3,4], writeIndex=2, so tail=[3,4] head=[5,6]
        // Wait, let me trace: capacity=4
        // append(1): storage[0]=1, writeIndex=1, count=1
        // append(2): storage[1]=2, writeIndex=2, count=2
        // append(3): storage[2]=3, writeIndex=3, count=3
        // append(4): storage[3]=4, writeIndex=0, count=4
        // append(5): storage[0]=5, writeIndex=1, count=4
        // append(6): storage[1]=6, writeIndex=2, count=4
        // storage = [5,6,3,4], writeIndex=2
        // tail = storage[2..<4] = [3,4], head = storage[0..<2] = [5,6]
        // elements = [3,4,5,6] -- chronological order!
        #expect(buf.elements == [3, 4, 5, 6])
    }

    @Test func capacityOne() {
        var buf = RingBuffer<Int>(capacity: 1)
        buf.append(42)
        #expect(buf.count == 1)
        #expect(buf.elements == [42])
        buf.append(99)
        #expect(buf.count == 1)
        #expect(buf.elements == [99])
    }

    @Test func countNeverExceedsCapacity() {
        var buf = RingBuffer<Int>(capacity: 3)
        for i in 1...100 {
            buf.append(i)
            #expect(buf.count <= buf.capacity)
        }
    }

    @Test func initFromArray() {
        let buf = RingBuffer(from: [10, 20, 30], capacity: 5)
        #expect(buf.count == 3)
        #expect(buf.elements == [10, 20, 30])
        #expect(buf.last == 30)
    }

    @Test func initFromArrayExceedingCapacity() {
        let buf = RingBuffer(from: [1, 2, 3, 4, 5], capacity: 3)
        #expect(buf.count == 3)
        #expect(buf.elements == [3, 4, 5])
        #expect(buf.last == 5)
    }
}
