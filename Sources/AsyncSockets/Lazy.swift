//
//  Lazy.swift
//  AsyncSockets
//
//  Created by Sean Erickson on 1/14/25.
//

import Foundation

final class Lazy<Value: Sendable>: @unchecked Sendable {
    
    private let lock = NSLock()
    private var _value: Value?
    private var factory: (@Sendable () -> Value)?
    
    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        
        if let _value {
            return _value
        }
        
        guard let nonNilFactory = factory else {
            fatalError("Factory is not set!")
        }
        
        let newValue = nonNilFactory()
        _value = newValue
        factory = nil
        
        return newValue
    }
    
    init(_ factory: @escaping @Sendable () -> Value) {
        self.factory = factory
        self._value = nil
    }
    
    init() {
        self.factory = nil
        self._value = nil
    }
    
    func set(_ factory: @escaping @Sendable () -> Value) {
        lock.withLock {
            self.factory = factory
        }
    }
}
