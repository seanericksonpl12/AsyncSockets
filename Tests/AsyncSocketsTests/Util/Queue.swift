import Foundation

final public class Queue<Element: Copyable>: @unchecked Sendable {
    
    #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
    private nonisolated(unsafe) var _lock = os_unfair_lock_s()
    
    @inline(__always)
    private func lock() {
        os_unfair_lock_lock(&_lock)
    }
    
    @inline(__always)
    private func unlock() {
        os_unfair_lock_unlock(&_lock)
    }
    #else
    private let _lock = NSLock()
    
    @inline(__always)
    private func lock() {
        _lock.lock()
    }
    
    @inline(__always)
    private func unlock() {
        _lock.unlock()
    }
    #endif
    
    final class Node: @unchecked Sendable {
        let value: Element
        var next: Node?
        var previous: Node?
        
        init(_ value: Element, next: Node? = nil, previous: Node? = nil) {
            self.value = value
            self.next = next
            self.previous = previous
        }
    }
    
    let limit: Int = 50
    private let id: UUID = UUID()
    private var _head: Node?
    private var _tail: Node?
    private var _count: Int = 0
    
    var count: Int {
        lock()
        defer { unlock() }
        return _count
    }
    
    public func addToFront(_ element: Element) {
        lock()
        defer { unlock() }
        
        if _count >= limit {
            print("limit reached.")
            return
        }
        
        let node = Node(element)
        if _head == nil {
            // Empty queue
            _head = node
            _tail = node
        } else {
            // Add to front
            node.next = _head
            _head?.previous = node
            _head = node
        }
        _count += 1
    }
    
    public func addToEnd(_ element: Element) {
        lock()
        defer { unlock() }
        
        if _count >= limit {
            print("limit reached.")
            return
        }
        
        let node = Node(element)
        if _head == nil {
            // Empty queue
            _head = node
            _tail = node
        } else {
            // Add to end
            node.previous = _tail
            _tail?.next = node
            _tail = node
        }
        _count += 1
    }
    
    public func popFirst() -> Element? {
        lock()
        defer { unlock() }
        
        guard let head = _head else {
            return nil
        }
        
        let value = head.value
        _count -= 1
        
        if head.next != nil {
            // More than one node
            head.next?.previous = nil
            _head = head.next
        } else {
            // Last node
            _head = nil
            _tail = nil
        }
        
        return value
    }
    
    public func popLast() -> Element? {
        lock()
        defer { unlock() }
        
        guard let tail = _tail else {
            return nil
        }
        
        let value = tail.value
        _count -= 1
        
        if tail.previous != nil {
            // More than one node
            tail.previous?.next = nil
            _tail = tail.previous
        } else {
            // Last node
            _head = nil
            _tail = nil
        }
        
        return value
    }
    
    public func clear() {
        lock()
        defer { unlock() }
        
        _head = nil
        _tail = nil
        _count = 0
    }
}

extension Queue: Equatable where Element: Equatable {
    public static func == (lhs: Queue<Element>, rhs: Queue<Element>) -> Bool {
        lhs.id == rhs.id
    }
}
