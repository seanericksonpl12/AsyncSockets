//
//  EventTests.swift
//  AsyncSockets
//
//  Created by Sean Erickson on 1/22/25.
//

import XCTest
@testable import AsyncSockets
import Network

final class EventTests: AsyncSocketsTestCase {
    
    func testConnect() async throws {
        let socket = Socket(url: URL(string: "ws://localhost:8000")!, options: .init(allowInsecureConnections: true))
        let connecting = XCTestExpectation(description: "received connecting event")
        let connected = XCTestExpectation(description: "received connected event")
        activeTasks.append(Task {
            for await event in socket.events() {
                switch event {
                case .stateChanged(let state):
                    switch state {
                    case .connecting:
                        connecting.fulfill()
                    case .connected:
                        connected.fulfill()
                    default:
                        XCTFail("\(state) not expected.")
                    }
                default:
                    XCTFail("Received \(event) instead of state change")
                }
            }
        })
        
        try await socket.connect()
        
        await fulfillment(of: [connecting, connected], timeout: 2, enforceOrder: true)
    }
    
    func testConnectConcurrent() async throws {
        let socketCount = 3
        let sockets = (0..<socketCount).map { _ in
            Socket(url: URL(string: "ws://localhost:8000")!, options: .init(allowInsecureConnections: true))
        }
        
        let connecting = Lock([Int](repeating: 0, count: socketCount))
        let connected = Lock([Int](repeating: 0, count: socketCount))
        
        activeTasks.append(Task {
            await withTaskGroup(of: Void.self) { group in
                for (index, socket) in sockets.enumerated() {
                    group.addTask {
                        for await event in socket.events() {
                            switch event {
                            case .stateChanged(let state):
                                switch state {
                                case .connecting:
                                    connecting.modify { $0[index] += 1 }
                                case .connected:
                                    connected.modify { $0[index] += 1 }
                                default:
                                    XCTFail("\(state) not expected.")
                                }
                            default:
                                XCTFail("Received \(event) instead of state change")
                            }
                        }
                    }
                }
                await group.waitForAll()
            }
        })
        
        
        for socket in sockets {
            try await socket.connect()
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual([Int](repeating: 1, count: sockets.count), connected.value)
        XCTAssertEqual([Int](repeating: 1, count: sockets.count), connecting.value)
    }
    
    func testClose() async throws {
        let socket = Socket(url: URL(string: "ws://localhost:8000")!, options: .init(allowInsecureConnections: true))
        let disconnected = XCTestExpectation(description: "received disconnected event")
        try await socket.connect()
        activeTasks.append(Task {
            for await event in socket.events() {
                switch event {
                case .stateChanged(let state):
                    switch state {
                    case .disconnected:
                        disconnected.fulfill()
                    default:
                        XCTFail("\(state) not expected.")
                    }
                default:
                    XCTFail("Received \(event) instead of state change")
                }
            }
        })
        
        try await socket.close()
        try await Task.sleep(nanoseconds: 100_000_000)
        await fulfillment(of: [disconnected], timeout: 2, enforceOrder: true)
    }
    
    func testCloseConcurrent() async throws {
        let socketCount = 3
        let sockets = (0..<socketCount).map { _ in
            Socket(url: URL(string: "ws://localhost:8000")!, options: .init(allowInsecureConnections: true))
        }
        
        let disconnected = Lock([Int](repeating: 0, count: socketCount))
        for socket in sockets {
            try await socket.connect()
        }
        
        activeTasks.append(Task {
            await withTaskGroup(of: Void.self) { group in
                for (index, socket) in sockets.enumerated() {
                    group.addTask {
                        for await event in socket.events() {
                            switch event {
                            case .stateChanged(let state):
                                switch state {
                                case .disconnected:
                                    disconnected.modify { $0[index] += 1 }
                                default:
                                    XCTFail("\(state) not expected.")
                                }
                            default:
                                XCTFail("Received \(event) instead of state change")
                            }
                        }
                    }
                }
                await group.waitForAll()
            }
        })
    
        for socket in sockets {
            try await socket.close()
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual([Int](repeating: 1, count: sockets.count), disconnected.value)
    }
}
