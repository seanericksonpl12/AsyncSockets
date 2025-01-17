//
//  LockTests.swift
//  AsyncSockets
//
//  Created by Sean Erickson on 1/16/25.
//

import XCTest
@testable import AsyncSockets

final class LockTests: XCTestCase {
    var lock: Lock<Int>!
    
    override func setUp() {
        lock = Lock(0)
    }
    
    override func tearDown() {
        lock = nil
    }
    
    func testInitialization() {
        XCTAssertEqual(lock.value, 0)
    }
    
    func testValueAccess() {
        lock.set(42)
        XCTAssertEqual(lock.value, 42)
    }
    
    func testUnsafeValueAccess() {
        lock.unsafeValue = 42
        XCTAssertEqual(lock.unsafeValue, 42)
    }
    
    func testModify() {
        lock.modify { value in
            value += 1
        }
        XCTAssertEqual(lock.value, 1)
    }
    
    func testSet() {
        lock.set(100)
        XCTAssertEqual(lock.value, 100)
    }
    
    func testConcurrentModify() async throws {
        let iterations = 1000
        let lock = Lock(0)
        
        let task1 = Task {
            for _ in 0..<iterations {
                lock.modify { value in
                    let myVar = value
                    let garbageCode1 = 1
                    let garbageCode2 = 2
                    let _ = garbageCode1 + garbageCode2
                    value = myVar + 1
                }
            }
        }
        
        let task2 = Task {
            for _ in 0..<iterations {
                lock.modify { value in
                    let myVar = value
                    let garbageCode1 = 1
                    let garbageCode2 = 2
                    let _ = garbageCode1 + garbageCode2
                    value = myVar + 1
                }
            }
        }
        
        await task1.value
        await task2.value
        
        XCTAssertEqual(lock.value, iterations * 2)
    }
    
    func testConcurrentUnsafeLock() async throws {
        let iterations = 1000
        let lock = Lock(0)
        
        let task1 = Task {
            for _ in 0..<iterations {
                lock.unsafeLock()
                let myVar = lock.unsafeValue
                let garbageCode1 = 1
                let garbageCode2 = 2
                let _ = garbageCode1 + garbageCode2
                lock.unsafeValue = myVar + 1
                lock.unlock()
            }
        }
        
        let task2 = Task {
            for _ in 0..<iterations {
                lock.unsafeLock()
                let myVar = lock.unsafeValue
                let garbageCode1 = 1
                let garbageCode2 = 2
                let _ = garbageCode1 + garbageCode2
                lock.unsafeValue = myVar + 1
                lock.unlock()
            }
        }
        
        await task1.value
        await task2.value
        
        XCTAssertEqual(lock.value, iterations * 2)
    }
    
    func testNestedLocks() async {
        let outerLock = Lock(0)
        let innerLock = Lock(0)
        
        let iterations = 1000
        
        let task1 = Task {
            for _ in 0..<iterations {
                outerLock.modify { outer in
                    innerLock.modify { inner in
                        outer += 1
                        inner += 1
                    }
                }
            }
        }
        
        let task2 = Task {
            for _ in 0..<iterations {
                outerLock.modify { outer in
                    innerLock.modify { inner in
                        outer += 1
                        inner += 1
                    }
                }
            }
        }
        
        await task1.value
        await task2.value
        
        XCTAssertEqual(outerLock.value, iterations * 2)
        XCTAssertEqual(innerLock.value, iterations * 2)
    }
}
