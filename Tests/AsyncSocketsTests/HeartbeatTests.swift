//
//  HeartbeatTests.swift
//  AsyncSockets
//
//  Created by Sean Erickson on 1/27/25.
//

import XCTest
@testable import AsyncSockets
import Network

final class HeartbeatTests: AsyncSocketsTestCase {
    
    func testHeartbeatInterval() async throws {
        let socket = Socket(host: "localhost", port: 8000, options: .init(allowInsecureConnections: true, heartbeatInterval: 2.0))
        try await socket.connect()
        var time = false
        let expectation = XCTestExpectation()
        
        activeTasks.append(Task {
            for try await message in socket.messages() {
                if !time {
                    XCTFail("Heartbeat early!")
                } else {
                    if case .pong = message {
                        expectation.fulfill()
                    } else {
                        XCTFail("Expected pong")
                    }
                }
            }
        })
        try await Task.sleep(nanoseconds: 1_000_000_000)
        time = true
        await fulfillment(of: [expectation], timeout: 2.0)
    }
    
    func testBadHeartbeatInterval() async {
        let socket = Socket(host: "localhost", port: 8000, options: .init(allowInsecureConnections: true, heartbeatInterval: -3))
        do {
            try await socket.connect()
            XCTFail()
        } catch {
            XCTAssertNotNil(error as? SocketError)
        }
    }
    
    func testMediumHeartbeat() async throws {
        let expectation = XCTestExpectation()
        let socket = Socket(host: "localhost", port: 8000, options: .init(allowInsecureConnections: true, heartbeatInterval: 1))
        try await socket.connect()
        var count = 0
        activeTasks.append(Task {
            for try await message in socket.messages() {
                if case .pong = message {
                    count += 1
                }
                if count >= 5 { expectation.fulfill() }
            }
        })
        await fulfillment(of: [expectation], timeout: 7.0)
    }
    
    func testLongHeartbeat() async throws {
        let expectation = XCTestExpectation()
        let socket = Socket(host: "localhost", port: 8000, options: .init(allowInsecureConnections: true, heartbeatInterval: 2.0))
        try await socket.connect()
        var count = 0
        activeTasks.append(Task {
            for try await message in socket.messages() {
                if case .pong = message {
                    count += 1
                }
                if count >= 15 { expectation.fulfill() }
            }
        })
        await fulfillment(of: [expectation], timeout: 33.0)
    }
    
    func testHeartbeatMissed() async throws {
        let socket = Socket(host: "localhost", port: 8000, options: .init(allowInsecureConnections: true, heartbeatInterval: 2.0))
        try await socket.connect()
        server.dropNext()
        activeTasks.append(Task {
            for try await _ in socket.messages() {
            }
        })

        await fulfillment(of: [server.closeExpectation], timeout: 5.0)
    }
}
