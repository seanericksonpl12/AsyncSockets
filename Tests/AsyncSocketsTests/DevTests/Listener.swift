//
//  Listener.swift
//  AsyncSockets
//
//  Created by Sean Erickson on 1/19/25.
//

import Network

import Foundation
import Network

import Foundation
import Network
import CryptoKit

class TestListener: @unchecked Sendable {
    private var listener: NWListener?
    
    init(port: UInt16) {
        do {
            // Create a listener on the specified port
            let parameters = NWParameters.tcp
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
            
            listener?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("Listener ready and waiting for connections on port \(port)")
                case .failed(let error):
                    print("Listener failed with error: \(error)")
                default:
                    break
                }
            }
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }
            
        } catch {
            print("Failed to create listener: \(error)")
        }
    }
    
    func start() {
        listener?.start(queue: .main)
        print("Listener started")
    }
    
    func stop() {
        listener?.cancel()
        print("Listener stopped")
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        print("New connection received")
        
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("Connection ready")
                self.receiveHTTPHeaders(on: connection)
            case .failed(let error):
                print("Connection failed with error: \(error)")
            case .cancelled:
                print("Connection cancelled")
            default:
                break
            }
        }
        
        connection.start(queue: .main)
    }
    
    private func receiveHTTPHeaders(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, context, isComplete, error in
            
            if let data = data, !data.isEmpty {
                if let request = String(data: data, encoding: .utf8) {
                    print("Received HTTP request:\n\(request)")
                    self.handleHTTPRequest(request, on: connection)
                }
            }
            
            if let error = error {
                print("Receive error: \(error)")
                connection.cancel()
                return
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
        
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { error in
            if let error = error {
                print("Failed to send handshake response: \(error)")
                connection.cancel()
            } else {
                print("Handshake complete, ready to echo messages")
                // self.handleWebSocketMessages(on: connection)
                self.receiveWebSocketMessage(on: connection)
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
    
    func receiveWebSocketMessage(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 2, maximumLength: 1024) { data, context, isComplete, error in
            guard let data = data, !data.isEmpty else {
                if let error = error {
                    print("Receive error: \(error)")
                }
                return
            }

            // Parse WebSocket frame (simplified for text messages)
            let firstByte = data[0]
            let fin = (firstByte & 0x80) != 0
            let opcode = firstByte & 0x0F

            guard opcode == 0x1 else {
                print("Unsupported opcode: \(opcode)")
                return
            }

            let secondByte = data[1]
            let isMasked = (secondByte & 0x80) != 0
            var payloadLength = Int(secondByte & 0x7F)

            var offset = 2
            if payloadLength == 126 {
                payloadLength = Int(data[offset...offset+1].withUnsafeBytes { $0.load(as: UInt16.self).bigEndian })
                offset += 2
            } else if payloadLength == 127 {
                payloadLength = Int(data[offset...offset+7].withUnsafeBytes { $0.load(as: UInt64.self).bigEndian })
                offset += 8
            }

            guard isMasked else {
                print("Client message must be masked")
                return
            }

            // Ensure there is enough data to apply the mask
            guard data.count >= offset + 4 + payloadLength else {
                print("Invalid frame: not enough data to apply the mask and extract payload")
                return
            }

            // Unmask the payload
            let maskingKey = Array(data[offset...offset+3]) // Convert Data to array of UInt8
            offset += 4
            let maskedPayload = data[offset..<offset+payloadLength]

            // Apply the mask
            let payload = maskedPayload.enumerated().map { (index, byte) -> UInt8 in
                return byte ^ maskingKey[index % 4]
            }

            if let message = String(bytes: payload, encoding: .utf8) {
                self.sendWebSocketMessage(message, on: connection)
                self.receiveWebSocketMessage(on: connection)
            } else {
                print("Invalid payload data")
            }
        }
    }
    
    func sendWebSocketMessage(_ message: String, on connection: NWConnection) {
        guard let data = message.data(using: .utf8) else { return }

        // WebSocket frame: text frame (0x1) with FIN bit set
        var frame = Data([0x81]) // 0x81 = FIN + Text Frame
        let length = data.count

        if length <= 125 {
            frame.append(UInt8(length))
        } else if length <= 65535 {
            frame.append(126)
            frame.append(contentsOf: UInt16(length).bytes)
        } else {
            frame.append(127)
            frame.append(contentsOf: UInt64(length).bytes)
        }

        frame.append(data)
        
        connection.send(content: frame, completion: .contentProcessed { error in
            if let error = error {
                print("Failed to send WebSocket message: \(error)")
            } else {
                print("Sent WebSocket message: \(message)")
            }
        })
    }
}

extension UInt16 {
    var bytes: [UInt8] {
        return withUnsafeBytes(of: self) { Array($0) }
    }
}

extension UInt64 {
    var bytes: [UInt8] {
        return withUnsafeBytes(of: self) { Array($0) }
    }
}
