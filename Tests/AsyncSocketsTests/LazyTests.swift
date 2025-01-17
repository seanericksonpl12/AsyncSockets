//
//  LazyTests.swift
//  AsyncSockets
//
//  Created by Sean Erickson on 1/16/25.
//

import XCTest
@testable import AsyncSockets

final class LazyTests: XCTestCase {
    
    var lazy: Lazy<Int>!
    
    override func setUp() {
        self.lazy = Lazy()
    }
    
    override func tearDown() {
        self.lazy = nil
    }
    
    func testSet() {
        let value = Lock(0)
        lazy.set({
            return value.value
        })
        value.set(1)
        
        XCTAssertEqual(lazy.value, 1)
    }
    
    func testInitWithFactory() {
            let lazy = Lazy { 42 }
            XCTAssertEqual(lazy.value, 42)
        }
        
        func testEmptyInitAndSetFactory() {
            lazy.set { 42 }
            XCTAssertEqual(lazy.value, 42)
        }
        
        func testFactoryOnlyCalledOnce() {
            let callCount = Lock(0)
            lazy.set {
                callCount.modify { $0 += 1 }
                return 42
            }
            
            // Access value multiple times
            _ = lazy.value
            _ = lazy.value
            _ = lazy.value
            
            XCTAssertEqual(callCount.value, 1)
        }
        
        func testConcurrentAccess() async throws {
            let lazy = Lazy<Int>()
            let callCount = Lock(0)
            
            lazy.set {
                callCount.modify{ $0 += 1 }
                return 42
            }
            
            // Create multiple tasks that access the value
            let task1 = Task {
                return lazy.value
            }
            
            let task2 = Task {
                return lazy.value
            }
            
            // Wait for both tasks and verify results
            let result1 = await task1.value
            let result2 = await task2.value
            
            XCTAssertEqual(result1, 42)
            XCTAssertEqual(result2, 42)
            XCTAssertEqual(callCount.value, 1)
        }
        
        func testSetFactoryAfterValueInitialized() {
            lazy.set { 42 }
            XCTAssertEqual(lazy.value, 42)
            
            // Setting a new factory after value is initialized should not change the value
            lazy.set { 84 }
            XCTAssertEqual(lazy.value, 42)
        }
        
        func testMultipleSetFactory() {
            lazy.set { 42 }
            lazy.set { 84 }
            
            // Should use the last factory set
            XCTAssertEqual(lazy.value, 84)
        }
        
        func testThreadSafetyWithHighConcurrency() async throws {
            let lazy = Lazy<Int>()
            let iterations = 1000
            let factoryCallCount = Lock(0)
            
            lazy.set {
                factoryCallCount.modify { $0 += 1 }
                return 42
            }
            
            // Create many concurrent tasks
            var tasks: [Task<Int, Never>] = []
            for _ in 0..<iterations {
                let task = Task {
                    return lazy.value
                }
                tasks.append(task)
            }
            
            // Wait for all tasks to complete
            for task in tasks {
                let result = await task.value
                XCTAssertEqual(result, 42)
            }
            
            // Factory should only be called once despite many concurrent accesses
            XCTAssertEqual(factoryCallCount.value, 1)
        }
    
}
