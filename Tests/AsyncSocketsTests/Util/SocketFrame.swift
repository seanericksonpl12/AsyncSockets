//
//  SocketFrame.swift
//  AsyncSockets
//
//  Created by Sean Erickson on 1/22/25.
//

import Foundation
import Network

struct SocketFrame {
    
    private let _data: Data
    
    let fin: Bool
    let opcode: NWProtocolWebSocket.Opcode
    let payloadLen: Int
    let mask: Bool
    let maskingKey: [UInt8]?
    let payload: Data
    
    var raw: Data { _data }
    
    init?(_ data: Data) {
        guard let firstByte = data[byte: 0] else { return nil }
        
        let fin = (firstByte & 0x80) != 0
        let opcodeBits = firstByte & 0x0F

        guard let opcode = NWProtocolWebSocket.Opcode(rawValue: opcodeBits) else {
            print("Unsupported opcode: \(opcodeBits)")
            return nil
        }

        guard let secondByte = data[byte: 1] else { return nil }
        let isMasked = (secondByte & 0x80) != 0
        var payloadLength = Int(secondByte & 0x7F)

        var offset = 2
        if payloadLength == 126 {
            guard data.count >= offset + 2 else { return nil }
            payloadLength = Int(data[offset...offset+1].withUnsafeBytes { $0.load(as: UInt16.self).bigEndian })
            offset += 2
        } else if payloadLength == 127 {
            guard data.count >= offset + 8 else { return nil }
            let longLength = data[offset...offset+7].withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
            guard longLength <= UInt64(Int.max) else { return nil }
            payloadLength = Int(longLength)
            offset += 8
        }

        let requiredLength = offset + (isMasked ? 4 : 0) + payloadLength
        guard data.count >= requiredLength else {
            print("Invalid frame: not enough data to apply the mask and extract payload")
            return nil
        }
        
        var payload = [UInt8]()
        
        if isMasked {
            let maskingKey = Array(data[offset...offset+3])
            offset += 4
            let maskedPayload = data[offset..<offset+payloadLength]
            payload = maskedPayload.enumerated().map { (index, byte) -> UInt8 in
                return byte ^ maskingKey[index % 4]
            }
            self.maskingKey = maskingKey
        } else {
            payload = Array(data[offset..<offset+payloadLength])
            self.maskingKey = nil
        }
        
        self._data = data
        self.opcode = opcode
        self.fin = fin
        self.mask = isMasked
        self.payloadLen = payloadLength
        self.payload = Data(payload)
    }

    init(fin: Bool = true, opcode: NWProtocolWebSocket.Opcode, payload: Data, mask: Bool = true) {
        self.fin = fin
        self.opcode = opcode
        self.payload = payload
        self.mask = mask
        self.payloadLen = payload.count
        
        // Generate random masking key if needed
        if mask {
            self.maskingKey = (0..<4).map { _ in UInt8.random(in: .min ... .max) }
        } else {
            self.maskingKey = nil
        }
        
        // Calculate frame size and create buffer
        var frameSize = 2 // First two bytes are always present
        let payloadLength = payload.count
        
        // Add extended payload length bytes
        if payloadLength > 65535 {
            frameSize += 8
        } else if payloadLength > 125 {
            frameSize += 2
        }
        
        // Add masking key size if masked
        if mask {
            frameSize += 4
        }
        
        // Add payload size
        frameSize += payloadLength
        
        var frameData = Data(capacity: frameSize)
        
        // First byte: FIN and opcode
        var firstByte: UInt8 = fin ? 0x80 : 0x00
        firstByte |= opcode.rawValue & 0x0F
        frameData.append(firstByte)
        
        // Second byte: MASK and payload length
        var secondByte: UInt8 = mask ? 0x80 : 0x00
        if payloadLength <= 125 {
            secondByte |= UInt8(payloadLength)
            frameData.append(secondByte)
        } else if payloadLength <= 65535 {
            secondByte |= 126
            frameData.append(secondByte)
            // Add 16-bit length
            withUnsafeBytes(of: UInt16(payloadLength).bigEndian) { frameData.append(contentsOf: $0) }
        } else {
            secondByte |= 127
            frameData.append(secondByte)
            // Add 64-bit length
            withUnsafeBytes(of: UInt64(payloadLength).bigEndian) { frameData.append(contentsOf: $0) }
        }
        
        // Add masking key if masked
        if let maskingKey = self.maskingKey {
            frameData.append(contentsOf: maskingKey)
            
            // Add masked payload
            var maskedPayload = [UInt8](repeating: 0, count: payloadLength)
            payload.enumerated().forEach { i, byte in
                maskedPayload[i] = byte ^ maskingKey[i % 4]
            }
            frameData.append(contentsOf: maskedPayload)
        } else {
            // Add unmasked payload
            frameData.append(payload)
        }
        
        self._data = frameData
    }

    // Convenience initializer for string payloads
    init(fin: Bool = true, opcode: NWProtocolWebSocket.Opcode = .text, text: String, mask: Bool = true) {
        self.init(fin: fin, opcode: opcode, payload: Data(text.utf8), mask: mask)
    }
    
    subscript(_ index: Int) -> UInt8 {
        _data[index]
    }
}

extension Data {
    subscript(byte index: Int) -> Element? {
        if self.count > index {
            return self[index]
        } else {
            return nil
        }
    }
}
