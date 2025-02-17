//
//  ConnectTests.swift
//  AsyncSockets
//
//  Created by Sean Erickson on 1/16/25.
//

import XCTest
@testable import AsyncSockets
import Network

final class ConnectTests: AsyncSocketsTestCase {
    
    func testConnectSuccessfulHostPort() async throws {
        let socket = Socket(host: self.localhost, port: self.serverport, options: .init(allowInsecureConnections: true))
        try await socket.connect()
        
        XCTAssertEqual(socket.state, .connected)
        XCTAssertEqual(socket.closeCode, .protocolCode(.noStatusReceived))
    }
    
    func testConnectSuccessfulUrl() async throws {
        guard let url = URL(string: "ws://localhost:8000") else {
            XCTFail("Invalid URL!")
            return
        }
        let socket = Socket(url: url, options: .init(allowInsecureConnections: true))
        try await socket.connect()
        
        XCTAssertEqual(socket.state, .connected)
        XCTAssertEqual(socket.closeCode, .protocolCode(.noStatusReceived))
    }
    
    func testConnectSuccessfulHostPortConcurrent() async throws {
        // Create multiple sockets
        let socketCount = 5
        var sockets: [Socket] = []
        for _ in 0..<socketCount {
            let socket = Socket(host: self.localhost, port: self.serverport, options: .init(allowInsecureConnections: true))
            sockets.append(socket)
        }
        
        // Connect all sockets concurrently
        try await withThrowingTaskGroup(of: Void.self) { group in
            for socket in sockets {
                group.addTask {
                    try await socket.connect()
                    
                    XCTAssertEqual(socket.state, .connected)
                    XCTAssertEqual(socket.closeCode, .protocolCode(.noStatusReceived))
                }
            }
            
            try await group.waitForAll()
        }
        
        // Clean up
        for socket in sockets {
            try? await socket.close()
        }
    }
    
    func testConnectSuccessfulUrlConcurrent() async throws {
        // Create multiple sockets
        let socketCount = 5
        var sockets: [Socket] = []
        for _ in 0..<socketCount {
            guard let url = URL(string: "ws://localhost:8000") else {
                XCTFail("Invalid URL!")
                return
            }
            let socket = Socket(url: url, options: .init(allowInsecureConnections: true))
            sockets.append(socket)
        }
        
        // Connect all sockets concurrently
        try await withThrowingTaskGroup(of: Void.self) { group in
            for socket in sockets {
                group.addTask {
                    try await socket.connect()
                    
                    XCTAssertEqual(socket.state, .connected)
                    XCTAssertEqual(socket.closeCode, .protocolCode(.noStatusReceived))
                }
            }
            
            try await group.waitForAll()
        }
        
        // Clean up
        for socket in sockets {
            try? await socket.close()
        }
    }
    
    func testConnectFailsWithInvalidHostError() async {
        let socket = Socket(host: "fdsafdsagdsah", port: self.serverport, options: .init(allowInsecureConnections: true))
        do {
            try await socket.connect()
            XCTFail("Expected connection to fail")
        } catch {
            XCTAssertTrue(error is SocketError)
        }
    }
    
    func testConnectFailsWithInvalidHostConcurrent() async {
        // Create multiple sockets with invalid hosts
        let socketCount = 5
        var sockets: [Socket] = []
        for _ in 0..<socketCount {
            let socket = Socket(host: "fdsafdsagdsah", port: self.serverport, options: .init(allowInsecureConnections: true))
            sockets.append(socket)
        }
        
        await withThrowingTaskGroup(of: Void.self) { group in
            for socket in sockets {
                group.addTask {
                    do {
                        try await socket.connect()
                        XCTFail("Expected connection to fail")
                    } catch {
                        XCTAssertTrue(error is SocketError)
                    }
                }
            }
        }
    }
    
    func testConnectFailsWithInvalidPort() async {
        // Create socket with invalid port
        let socket = Socket(host: self.localhost, port: 1, options: .init(allowInsecureConnections: true))
        
        do {
            try await socket.connect()
            XCTFail("Expected connection to fail")
        } catch {
            XCTAssertTrue(error is SocketError)
        }
    }
    
    func testConnectFailsWithInvalidPortConcurrent() async throws {
        // Create multiple sockets with invalid ports
        let socketCount = 5
        var sockets: [Socket] = []
        for i in 0..<socketCount {
            let socket = Socket(host: self.localhost, port: 1, options: .init(allowInsecureConnections: true))
            sockets.append(socket)
        }
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            for socket in sockets {
                group.addTask {
                    do {
                        try await socket.connect()
                        XCTFail("Expected connection to fail")
                    } catch {
                        XCTAssertTrue(error is SocketError)
                    }
                }
            }
            try await group.waitForAll()
        }
    }
    
    func testConnectFailsWithInvalidUrl() async throws {
        guard let url = URL(string: "ws://invalidurlforsocket:8000") else {
            XCTFail("Failed to create url")
            return
        }
        
        let socket = Socket(url: url, options: .init(allowInsecureConnections: true))
        do {
            try await socket.connect()
            XCTFail("Expected connection to fail")
        } catch {
            XCTAssertTrue(error is SocketError)
        }
    }
    
    func testConnectFailsWithInvalidUrlConcurrent() async throws {
        // Create multiple sockets with invalid ports
        let socketCount = 5
        var sockets: [Socket] = []
        for _ in 0..<socketCount {
            guard let url = URL(string: "ws://invalidurlforsocket:8000") else {
                XCTFail("Failed to create url")
                return
            }
            let socket = Socket(url: url, options: .init(allowInsecureConnections: true))
            sockets.append(socket)
        }
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            for socket in sockets {
                group.addTask {
                    do {
                        try await socket.connect()
                        XCTFail("Expected connection to fail")
                    } catch {
                        XCTAssertTrue(error is SocketError)
                    }
                }
            }
            try await group.waitForAll()
        }
    }
    
    func testMultipleConnectCallsFail() async throws {
        let socket = Socket(host: self.localhost, port: self.serverport, options: .init(allowInsecureConnections: true))
        // First connect should succeed
        try await socket.connect()
        
        // Second connect should be ignored
        do {
            try await socket.connect()
            XCTAssertEqual(socket.state, .connected)
        } catch {
            XCTFail()
        }
    }
    
    func testMultipleConnectCallsFailConcurrent() async throws {
        let socket = Socket(host: self.localhost, port: self.serverport, options: .init(allowInsecureConnections: true))
        let connectCount = 5
        let errorCount = Lock(0)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    do {
                        try await socket.connect()
                    } catch {
                        errorCount.modify { $0 += 1 }
                    }
                }
            }
            try await group.waitForAll()
        }
        
        XCTAssertEqual(socket.state, .connected)
        XCTAssertEqual(errorCount.value, connectCount - 1)
    }
}

