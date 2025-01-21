//
//  CloseTests.swift
//  AsyncSockets
//
//  Created by Sean Erickson on 1/16/25.
//

import XCTest
@testable import AsyncSockets
import Network

final class CloseTests: XCTestCase {

    func testSynchronousClose() async throws {
        let socket = Socket(url: URL(string: "ws://localhost:8000")!, options: .init(allowInsecureConnections: true))
        try await socket.connect()
        
        // Test synchronous close
        DispatchQueue.main.sync {
            socket.close()
        }
        
        // Give a small delay for the close to process
        try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
        XCTAssertEqual(socket.state, .disconnected)
    }
    
    func testSynchronousCloseConcurrent() async throws {
        // Create multiple sockets
        let socketCount = 5
        let sockets = (0..<socketCount).map { _ in
            Socket(url: URL(string: "ws://localhost:8000")!, options: .init(allowInsecureConnections: true))
        }
        
        // Connect all sockets
        for socket in sockets {
            try await socket.connect()
        }
        
        // Close all sockets concurrently
        try await withThrowingTaskGroup(of: Void.self) { group in
            for socket in sockets {
                group.addTask {
                    DispatchQueue(label: "\(ObjectIdentifier(socket))").sync {
                        socket.close()
                    }
                    
                    // Give a small delay for the close to process
                    try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
                    XCTAssertEqual(socket.state, .disconnected)
                }
            }
            
            try await group.waitForAll()
        }
    }
    
    func testAsynchronousClose() async throws {
        let socket = Socket(url: URL(string: "ws://localhost:8000")!, options: .init(allowInsecureConnections: true))
        try await socket.connect()
        
        // Test asynchronous close
        try await socket.close()
        
        XCTAssertEqual(socket.state, .disconnected)
    }
    
    func testAsynchronousCloseConcurrent() async throws {
        // Create multiple sockets
        let socketCount = 5
        let sockets = (0..<socketCount).map { _ in
            Socket(url: URL(string: "ws://localhost:8000")!, options: .init(allowInsecureConnections: true))
        }
        
        // Connect all sockets
        for socket in sockets {
            try await socket.connect()
        }
        
        // Close all sockets concurrently
        try await withThrowingTaskGroup(of: Void.self) { group in
            for socket in sockets {
                group.addTask {
                    try await socket.close()
                    
                    XCTAssertEqual(socket.state, .disconnected)
                }
            }
            
            try await group.waitForAll()
        }
    }
    
    func testCloseWithCustomCode() async throws {
        let socket = Socket(url: URL(string: "ws://localhost:8000")!, options: .init(allowInsecureConnections: true))
        try await socket.connect()
        
        // Test close with custom code
        let closeCode = CloseCode.protocolCode(.goingAway)
        try await socket.close(withCode: closeCode)
        
        XCTAssertEqual(socket.state, .disconnected)
        XCTAssertEqual(socket.closeCode, closeCode)
    }
    
    func testCloseWithCustomCodeConcurrent() async throws {
        // Create multiple sockets
        let socketCount = 5
        let sockets = (0..<socketCount).map { _ in
            Socket(url: URL(string: "ws://localhost:8000")!, options: .init(allowInsecureConnections: true))
        }
        
        // Connect all sockets
        for socket in sockets {
            try await socket.connect()
        }
        
        // Close all sockets concurrently with different close codes
        let closeCodes: [CloseCode] = [
            .protocolCode(.goingAway),
            .protocolCode(.normalClosure),
            .protocolCode(.protocolError),
            .protocolCode(.unsupportedData),
            .protocolCode(.policyViolation)
        ]
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (socket, closeCode) in zip(sockets, closeCodes) {
                group.addTask {
                    try await socket.close(withCode: closeCode)
                    
                    XCTAssertEqual(socket.state, .disconnected)
                    XCTAssertEqual(socket.closeCode, closeCode)
                }
            }
            
            try await group.waitForAll()
        }
    }
    
    func testCloseWhenNotConnected() async throws {
        let socket = Socket(url: URL(string: "ws://localhost:8000")!, options: .init(allowInsecureConnections: true))
        // Test closing without connecting
        try await socket.close()
        
        XCTAssertEqual(socket.state, .disconnected)
    }
    
    func testCloseWhenNotConnectedConcurrent() async throws {
        // Create multiple sockets
        let socketCount = 5
        var sockets = (0..<socketCount).map { _ in
            Socket(url: URL(string: "ws://localhost:8000")!, options: .init(allowInsecureConnections: true))
        }
        
        // Close all sockets concurrently without connecting
        try await withThrowingTaskGroup(of: Void.self) { group in
            for socket in sockets {
                group.addTask {
                    try await socket.close()
                    
                    XCTAssertEqual(socket.state, .disconnected)
                }
            }
            
            try await group.waitForAll()
        }
    }
    
    func testMultipleCloseCalls() async throws {
        let socket = Socket(url: URL(string: "ws://localhost:8000")!, options: .init(allowInsecureConnections: true))
        
        try await socket.connect()
        
        // First close
        try await socket.close()
        
        // Second close should not throw
        try await socket.close()
        
        XCTAssertEqual(socket.state, .disconnected)
    }
    
    func testMultipleCloseCallsConcurrent() async throws {
        let socket = Socket(url: URL(string: "ws://localhost:8000")!, options: .init(allowInsecureConnections: true))
        try await socket.connect()
        
        // Try multiple concurrent close calls on the same socket
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    try? await socket.close()
                }
            }
            
            try await group.waitForAll()
        }
        
        XCTAssertEqual(socket.state, .disconnected)
    }
    
    func testCloseTerminatesMessageSequence() async throws {
        let socket = Socket(url: URL(string: "ws://localhost:8000")!, options: .init(allowInsecureConnections: true))
        try await socket.connect()
        
        let messageCount = 3
        var receivedCount = 0
        
        // Create a task to send messages and then close
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second delay
            for i in 1...messageCount {
                try? await socket.send("Message \(i)")
            }
            try? await socket.close()
        }
        
        // Test that message sequence terminates after close
        for try await message in socket.messages() {
            receivedCount += 1
        }
        
        // Verify we received messages until close
        XCTAssertLessThanOrEqual(receivedCount, messageCount)
    }
    
    func testCloseTerminatesMessageSequenceConcurrent() async throws {
        // Create multiple sockets
        let socketCount = 3
        var sockets = (0..<socketCount).map { _ in
            Socket(url: URL(string: "ws://localhost:8000")!, options: .init(allowInsecureConnections: true))
        }
        
        // Connect all sockets
        for socket in sockets {
            try await socket.connect()
        }
        
        let messageCount = 3
        let receivedCounts = Lock<[Int]>(Array(repeating: 0, count: socketCount))
        
        // Create tasks to send messages and close for each socket
        for (index, socket) in sockets.enumerated() {
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second delay
                for i in 1...messageCount {
                    try? await socket.send("Socket\(index)Message\(i)")
                }
                try? await socket.close()
            }
        }
        
        // Test message sequences concurrently
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (index, socket) in sockets.enumerated() {
                group.addTask { @Sendable in
                    for try await message in socket.messages() {
                        receivedCounts.modify { $0[index] += 1 }
                    }
                }
            }
            
            try await group.waitForAll()
        }
        
        // Verify counts
        for count in receivedCounts.value {
            XCTAssertLessThanOrEqual(count, messageCount)
        }
    }
}

