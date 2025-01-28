//
//  ServerConnection.swift
//  AsyncSockets
//
//  Created by Sean Erickson on 1/24/25.
//


import Network
import Foundation
import CryptoKit
@testable import AsyncSockets

public final class ServerConnection: Sendable {
    
    private let buffer = Queue<Data>()
    private let sendQueue = DispatchQueue(label: "com.asyncsockets.server.send")
    private let connection: NWConnection
    
    init(connection: NWConnection) {
        self.connection = connection
        self.connection.parameters.defaultProtocolStack.applicationProtocols.insert(WebSocketProtocolOptions(), at: 0)
    }
    
    func start() {
        self.connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                print("Connection ready")
                self.receiveHTTPHeaders(on: connection)
            case .failed(let error):
                print("Connection failed with error: \(error)")
                connection.cancel()
            case .cancelled:
                print("Connection cancelled")
            default:
                break
            }
        }
        connection.start(queue: .main)
    }
    
    private func receiveHTTPHeaders(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65535) { [weak self] data, context, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Receive error: \(error)")
                connection.cancel()
                return
            }
            
            if let data = data, !data.isEmpty {
                if let request = String(data: data, encoding: .utf8) {
                    print("Received HTTP request:\n\(request)")
                    self.handleHTTPRequest(request, on: connection)
                }
            }
        }
    }
    
    private func handleHTTPRequest(_ request: String, on connection: NWConnection) {
        guard request.lowercased().contains("upgrade: websocket"),
              let key = extractWebSocketKey(from: request) else {
            print("Invalid WebSocket upgrade request, closing connection")
            connection.cancel()
            return
        }
        
        let acceptKey = generateWebSocketAcceptKey(for: key)
        let response = """
        HTTP/1.1 101 Switching Protocols\r
        Upgrade: websocket\r
        Connection: upgrade\r
        Sec-WebSocket-Accept: \(acceptKey)\r
        \r\n
        """
        
        print("Sending handshake response:\n\(response)")
        
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                print("Failed to send handshake response: \(error)")
                connection.cancel()
            } else {
                print("Handshake complete, ready to echo messages")
                self.startContinuousReceive()
            }
        })
    }
    
    private func extractWebSocketKey(from request: String) -> String? {
        let lines = request.split(separator: "\r\n")
        for line in lines {
            if line.hasPrefix("Sec-WebSocket-Key:") {
                return line.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
    
    private func generateWebSocketAcceptKey(for key: String) -> String {
        let magicString = key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let hash = Insecure.SHA1.hash(data: magicString.data(using: .utf8)!)
        return Data(hash).base64EncodedString()
    }
    
    private func startContinuousReceive() {
        guard connection.state == .ready else { return }
        
        self.receiveWebSocketMessage()
        self.startQueueProcessing()
    }
    
    private func receiveWebSocketMessage() {
        guard connection.state == .ready else {
            return
        }
        
        connection.receive(minimumIncompleteLength: 2, maximumLength: 65535) { [weak self] data, context, isComplete, error in
            guard let self = self else { return }
            if connection.state == .ready {
                self.receiveWebSocketMessage()
            }
            
            if let error = error {
                print("Receive error: \(error)")
                connection.cancel()
                return
            }
            
            if let data = data, !data.isEmpty, var frame = SocketFrame(data) {
                // Socket Framing - Probably doesn't work for extended payload lengths
                var currentFrame = [UInt8]()
                var i = 0
                for byte in data {
                    i += 1
                    if currentFrame.count < 6 + frame.payloadLen {
                        currentFrame.append(byte)
                    }
                    
                    if currentFrame.count == 6 + frame.payloadLen {
                        let dataToSend = Data(currentFrame)
                        self.buffer.addToFront(dataToSend)
                        currentFrame = []
                        if let newFrame = SocketFrame(Data(data[i..<data.count])) {
                            frame = newFrame
                        }
                    }
                }
            }
        }
    }
    
    func startQueueProcessing() {
        sendQueue.async {
            while true {
                guard let data = self.buffer.popLast(), let frame = SocketFrame(data) else { continue }
                let opcodeToSend = frame.opcode == .ping ? .pong : frame.opcode
                let context = NWConnection.ContentContext(identifier: "serverContext", metadata: [NWProtocolWebSocket.Metadata(opcode: opcodeToSend)])
                
                switch frame.opcode {
                case .cont:
                    break
                case .text:
                    self.sendWebSocketMessage(frame, with: context)
                case .binary:
                    self.sendWebSocketMessage(frame, with: context)
                case .close:
                    self.connection.cancel()
                case .ping:
                    self.sendWebSocketMessage(frame, with: context)
                case .pong:
                    print("server received pong")
                @unknown default:
                    fatalError()
                }
            }
        }
    }

    func sendWebSocketMessage(_ data: SocketFrame, with context: NWConnection.ContentContext?) {
        guard connection.state == .ready else { return }
        
        let opcodeToSend = data.opcode == .ping ? .pong : data.opcode
        let payloadToSend = data.opcode == .ping ? "pong".data(using: .utf8) ?? data.payload : data.payload
        let frame = SocketFrame(opcode: opcodeToSend, payload: payloadToSend, mask: false)
        connection.send(content: frame.raw, contentContext: context ?? .defaultMessage, completion: .contentProcessed { [weak self] error in
            if let error = error {
                print("Failed to send WebSocket message: \(error)")
                self?.connection.cancel()
            }
        })
    }
    
    private func printbinary(_ data: Data) {
        
        var value = ""
        for (i, byte) in data.enumerated() {
            if i % 4 == 0 && i != 0 {
                value += "\n"
            }
            var byteString = String(byte, radix: 2)
            while byteString.count < 8 { byteString = "0" + byteString }
            value += byteString
            value += " "
        }
        var payloadInfo: String?
        if let frame = SocketFrame(data) {
            payloadInfo = "\npayload len: \(frame.payloadLen)\npayload: \(String(data: frame.payload, encoding: .utf8) ?? "nil")"
        }
        debugLog("_______________________________________________\nData of size \(data)\(payloadInfo ?? "")\n\(value)\n_______________________________________________")
    }
}
