//
//  AsyncPerformanceTests.swift
//  AsyncSockets
//
//  Created by Sean Erickson on 1/14/25.
//

import Foundation
import XCTest
@testable import AsyncSockets

final class AsyncPerformanceTests: XCTestCase {
    
    var url: URL!
    var echoUrl: URL!
    
    override func setUpWithError() throws {
        self.url = URL(string: "ws://localhost:8000/ws")
        self.echoUrl = URL(string: "wss://echo.websocket.org/")
    }
    
    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func testNothing() async throws {
        let socket = Socket(url: self.url, options: .init(allowInsecureConnections: true))
        
    }
    
    @MainActor
    func testSocketMessageSequence() async throws {
        let socket = Socket(url: self.url, options: .init(allowInsecureConnections: true))
//        Task {
//            do {
//                try await socket.connect()
//            } catch { print(error) }
//        }
        Task {
            try await socket.send("preconnect")
        }
        try await socket.connect()
        let stream1 = socket.messages()
        let stream2 = socket.messages()
        Task {
            
            for i in 0..<4 {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                try await socket.send("hello world number \(i)")
            }
            
            // try await Task.sleep(nanoseconds: 1_000_000_000)
            try await socket.close()
            
        }
       
        Task {
            
            do {
                for try await message in stream2 {
                    switch message {
                    case .data(let data):
                        print("stream 2 received data: \(String(data: data, encoding: .utf8) ?? "nil")")
                    case .string(let string):
                        print("stream 2 received string: \(string)")
                    }
                }
            } catch {
                print("Caught error: \(error)")
            }
            print("Closed!")
        }
        
        Task {
            do {
                for try await message in stream1 {
                    switch message {
                    case .data(let data):
                        print("stream 1 received data: \(String(data: data, encoding: .utf8) ?? "nil")")
                    case .string(let string):
                        print("stream 1 received string: \(string)")
                    }
                }
            } catch {
                print("Caught error: \(error)")
            }
            print("Closed!")
        }
        try await Task.sleep(nanoseconds: 10_000_000_000)
    }
    
    func testGenericSequence() async throws {
        let socket = Socket(url: self.url, options: .init(allowInsecureConnections: true))
        try await socket.connect()
        struct TestStruct: Codable {
            let value: String
        }
        let encoder = JSONEncoder()
        Task {
            do {
                for i in 0..<4 {
                    let value = TestStruct(value: "hello")
                    // try await socket.send("hello!")
                    try await socket.send(encoder.encode(value))
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                }
                try await socket.close()
            } catch {
                print("caught error, closing")
                try await socket.close()
            }
        }
        
        let stream = socket.messages(ofType: TestStruct.self)
        do {
            print("started")
            for try await message in stream {
                print(message)
            }
            print("finished")
        } catch {
            print("error: \(error)")
        }
    }
    
    func testReleasingSocket() async throws {
        var socket: Socket = Socket(url: URL(string: "ws://localhost:8000/ws")!, options: .init(allowInsecureConnections: true))
        
        try await socket.connect()
        
        
        let task1 = Task {
            do {
                let value = try await socket.receive()
                // XCTFail()
            } catch {
                // XCTFail(String(describing: error))
            }
        }
        
        let task2 = Task {
            do {
                let value = try await socket.receive()
                XCTFail()
            } catch {
                XCTFail(String(describing: error))
            }
        }
        
        try await Task.sleep(nanoseconds: 1_000_000_000)
        // socket = nil
    }
    
    func testConnect() async throws {
        let task = URLSession.shared.webSocketTask(with: url)
        
        task.resume()
        task.receive { message in
            switch message {
            case .success(let success):
                switch success {
                case .string(let val):
                    print(val)
                case .data(let data):
                    print(String(data: data, encoding: .utf8))
                @unknown default:
                    fatalError()
                }
            case .failure(let failure):
                print("error: \(failure)")
            }
        }
        try await Task.sleep(nanoseconds: 5_000_000_00)
    }
    
    func testNWSocket() throws {
        let url = URL(string: "wss://echo.websocket.org/")!
        self.measure {
            let exp = expectation(description: "Finished")
            Task {
                let socket = Socket(url: url)
                try await socket.connect()
                exp.fulfill()
            }
            wait(for: [exp], timeout: 200.0)
        }
    }
    
    func testFoundationSocket() throws {
        
        final class TestDelegate: NSObject, URLSessionWebSocketDelegate {
            let exp: XCTestExpectation
            
            init(exp: XCTestExpectation) {
                self.exp = exp
            }
            
            func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
                exp.fulfill()
            }
            
            func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
                exp.fulfill()
            }
        }
        
        let url = URL(string: "wss://echo.websocket.org/")!
        self.measure {
            let exp = expectation(description: "Finished")
            Task {
                let task = URLSession.shared.webSocketTask(with: url)
                task.delegate = TestDelegate(exp: exp)
                task.resume()
            }
            wait(for: [exp], timeout: 200.0)
        }
    }
    
}
