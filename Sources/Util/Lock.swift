//
//  Lock.swift
//  AsyncSockets
//
//  Created by Sean Erickson on 1/12/25.
//

import Foundation

final class Lock<Value: Sendable>: @unchecked Sendable {
    private let _lock = NSLock()
    private var _value: Value
    private var onDeinit: (Value) -> Void = { _ in }
    
    deinit {
        onDeinit(_value)
    }
    
    var value: Value {
        _lock.withLock { _value }
    }
    
    var unsafeValue: Value {
        get {
            _value
        }
        set {
            _value = newValue
        }
    }
    
    func unsafeLock() {
        _lock.lock()
    }
    
    func unlock() {
        _lock.unlock()
    }
    
    func set(_ newValue: Value) {
        _lock.withLock { _value = newValue }
    }
    
    func modify(_ transform: (inout Value) -> Void) {
        _lock.withLock { transform(&_value) }
    }
    
    init(_ value: Value) {
        self._value = value
    }
}
