//
//  SendTests.swift
//  AsyncSockets
//
//  Created by Sean Erickson on 1/16/25.
//

import XCTest
@testable import AsyncSockets
import Network

final class SendTests: AsyncSocketsTestCase {
    
    func testSendString() async throws {
        let socket = Socket(host: self.localhost, port: self.serverport, options: .init(allowInsecureConnections: true))
        try await socket.connect()
        
        try await socket.send("Hello, World!")

        XCTAssertEqual(socket.state, .connected)
    }
    
    func testSendStringConcurrent() async throws {
        let socket = Socket(host: self.localhost, port: self.serverport, options: .init(allowInsecureConnections: true))
        try await socket.connect()
        
        let messages = (1...5).map { "Message \($0)" }
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            for message in messages {
                group.addTask {
                    try await socket.send(message)
                }
            }
            
            try await group.waitForAll()
        }

        XCTAssertEqual(socket.state, .connected)
        
        // Clean up
        try? await socket.close()
    }
    
    func testSendData() async throws {
        let socket = Socket(host: self.localhost, port: self.serverport, options: .init(allowInsecureConnections: true))
        try await socket.connect()
        
        // Test sending data
        let data = "Test Data".data(using: .utf8)!
        try await socket.send(data)

        
        XCTAssertEqual(socket.state, .connected)
    }
    
    func testSendDataConcurrent() async throws {
        let socket = Socket(host: self.localhost, port: self.serverport, options: .init(allowInsecureConnections: true))
        try await socket.connect()
        
        // Send multiple data packets concurrently
        let dataPackets = (1...5).map { "Data Packet \($0)".data(using: .utf8)! }
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            for data in dataPackets {
                group.addTask {
                    try await socket.send(data)
                }
            }
            
            try await group.waitForAll()
        }
        
        XCTAssertEqual(socket.state, .connected)
        
        // Clean up
        try? await socket.close()
    }
    
    func testSendFailsWhenNotConnected() async {
        let socket = Socket(host: self.localhost, port: self.serverport, options: .init(allowInsecureConnections: true))
        // Try to send without connecting
        do {
            try await socket.send("Test message")
            XCTFail("Expected send to fail when not connected")
        } catch {
            XCTAssertTrue(error is SocketError)
            if let socketError = error as? SocketError {
                switch socketError {
                case .wsError(let error):
                    XCTAssertEqual(error.domain, .WSConnectionDomain)
                    XCTAssertEqual(error.code, .socketNotConnected)
                default:
                    XCTFail("Unexpected error type")
                }
            }
        }
    }
    
    func testSendFailsWhenNotConnectedConcurrent() async {
        let socket = Socket(host: self.localhost, port: self.serverport, options: .init(allowInsecureConnections: true))
        
        // Try multiple sends concurrently without connecting
        await withThrowingTaskGroup(of: Void.self) { group in
            for i in 1...5 {
                group.addTask {
                    do {
                        try await socket.send("Test message \(i)")
                        XCTFail("Expected send to fail when not connected")
                    } catch {
                        XCTAssertTrue(error is SocketError)
                        if let socketError = error as? SocketError {
                            switch socketError {
                            case .wsError(let error):
                                XCTAssertEqual(error.domain, .WSConnectionDomain)
                                XCTAssertEqual(error.code, .socketNotConnected)
                            default:
                                XCTFail("Unexpected error type")
                            }
                        }
                    }
                }
            }
        }
        
        // Clean up
        try? await socket.close()
    }
    
    func testSendFailsAfterClose() async throws {
        let socket = Socket(host: self.localhost, port: self.serverport, options: .init(allowInsecureConnections: true))
        
        try await socket.connect()
        try await socket.close()
        
        do {
            try await socket.send("Test message")
            XCTFail("Expected send to fail after close")
        } catch {
            XCTAssertTrue(error is SocketError)
            if let socketError = error as? SocketError {
                switch socketError {
                case .wsError(let error):
                    XCTAssertEqual(error.domain, .WSConnectionDomain)
                    XCTAssertEqual(error.code, .socketNotConnected)
                default:
                    XCTFail("Unexpected error type")
                }
            }
        }
    }
    
    func testSendFailsAfterCloseConcurrent() async throws {
        
            let socket = Socket(host: self.localhost, port: self.serverport, options: .init(allowInsecureConnections: true))
        do {
            try await socket.connect()
            try await socket.close()
            print("closed")
            // Try multiple sends concurrently after closing
            await withThrowingTaskGroup(of: Void.self) { group in
                for i in 1...5 {
                    group.addTask {
                        do {
                            try await socket.send("Test message \(i)")
                            XCTFail("Expected send to fail after close")
                        } catch {
                            XCTAssertTrue(error is SocketError)
                            if let socketError = error as? SocketError {
                                switch socketError {
                                case .wsError(let error):
                                    XCTAssertEqual(error.domain, .WSConnectionDomain)
                                    XCTAssertEqual(error.code, .socketNotConnected)
                                default:
                                    XCTFail("Unexpected error type")
                                }
                            }
                        }
                    }
                }
            }
        } catch {
            print(error)
            XCTFail()
        }
    }
    
    func testPing() async throws {
        let socket = Socket(host: self.localhost, port: self.serverport, options: .init(allowInsecureConnections: true))
        
        try await socket.connect()
        
        // Test sending ping
        try await socket.ping()
        
        XCTAssertEqual(socket.state, .connected)
    }
    
    func testPingConcurrent() async throws {
        let socket = Socket(host: self.localhost, port: self.serverport, options: .init(allowInsecureConnections: true))
        try await socket.connect()
        
        // Send multiple pings concurrently
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 1...5 {
                group.addTask {
                    try await socket.ping()
                }
            }
            
            try await group.waitForAll()
        }
        
        XCTAssertEqual(socket.state, .connected)
        
        // Clean up
        try? await socket.close()
    }
}

