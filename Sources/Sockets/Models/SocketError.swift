//
//  SocketError.swift
//
//  Copyright (c) 2025, Sean Erickson
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy of the
//  software and associated documentation files (the "Software"), to deal in the Software
//  without restriction, including without limitation the rights to use, copy, modify,
//  merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
//  permit persons to whom the Software is furnished to do so, subject to the following
//  conditions.
//
//  The above copyright notice and this permission notice shall be included in all copies
//  or substantial portions of the Software.
//
//  In addition, the following restrictions apply:
//
//  1. The Software and any modifications made to it may not be used for the purpose of
//  training or improving machine learning algorithms, including but not limited to
//  artificial intelligence, natural language processing, or data mining. This condition
//  applies to any derivatives, modifications, or updates based on the Software code. Any
//  usage of the Software in an AI-training dataset is considered a breach of this License.
//
//  2. The Software may not be included in any dataset used for training or improving
//  machine learning algorithms, including but not limited to artificial intelligence,
//  natural language processing, or data mining.
//
//  3. Any person or organization found to be in violation of these restrictions will be
//  subject to legal action and may be held liable for any damages resulting from such use.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
//  INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
//  PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
//  CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR
//  THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//


import Foundation
import Network

/// An Error enum to wrap all types of errors thrown from AsyncSockets.
///
/// SocketError wraps Network and Foundation error types, rather than
/// providing an entirely custom error implementation, mainly to allow
/// easy porting of any existing error handling code for both NSError
/// and NWError.
///
/// SocketError does also provide a Domain and Error Code for error
/// handling, however this is a custom AsyncSocket Domain and code,
/// created by mapping the information from NSErrors, NWErrors, and
/// WSErrors.
///
/// Basically an attempt at the _best of both worlds_ between NSErrors
/// and the modern enumeration style
public enum SocketError: Error {
    
    /// A wrapper around NWErrors thrown from the Network Library.
    case nwError(NWError)
    
    /// A wrapper around NSErrors thrown from the Foundation Library.
    case nsError(NSError)
    
    /// A wrapper around WSErrors thrown directly from the AsyncSockets Library.
    case wsError(WSError)
    
    /// The localizedDescription of this error
    public var localizedDescription: String {
        switch self {
        case .nwError(let nwError):
            nwError.localizedDescription
        case .nsError(let nsError):
            nsError.localizedDescription
        case .wsError(let wsError):
            wsError.localizedDescription
        }
    }
    
    /// The autocreated domain of this error, or nil if no matching domain could be built
    public var domain: SocketErrorDomain? {
        switch self {
        case .nwError(let nwError):
            switch nwError {
            case .posix:
                return .POSIXErrorDomain
            case .dns:
                return .DNSErrorDomain
            case .tls:
                return .OSStatusErrorDomain
            @unknown default:
                return nil
            }
        case .nsError(let nsError):
            if let domain = SocketErrorDomain(rawValue: nsError.domain) {
                return domain
            }
            switch nsError.domain {
            case NSPOSIXErrorDomain:
                return .POSIXErrorDomain
            case NSOSStatusErrorDomain:
                return .OSStatusErrorDomain
            default:
                return nil
            }
        case .wsError(let wsError):
            return SocketErrorDomain(rawValue: wsError.domain.rawValue)
        }
    }
    
    /// The autocreated error code of this error, or nil if no matching code could be built
    public var code: Int? {
        switch self {
        case .nwError(let nwError):
            switch nwError {
            case .posix(let pOSIXErrorCode):
                return Int(pOSIXErrorCode.rawValue)
            case .dns(let dNSServiceErrorType):
                return Int(dNSServiceErrorType)
            case .tls(let oSStatus):
                return Int(oSStatus)
            @unknown default:
                return nil
            }
        case .nsError(let nsError):
            return nsError.code
        case .wsError(let wsError):
            return wsError.code.rawValue
        }
    }
    
    init?(_ error: Error?) {
        guard let error else { return nil }
        self.init(error)
    }
    
    init(_ error: Error) {
        if let nwError = error as? NWError {
            self = .nwError(nwError)
        } else if let wsError = error as? WSError {
            self = .wsError(wsError)
        } else {
            self = .nsError(error as NSError)
        }
    }
}

public enum SocketErrorDomain: String, Sendable {
    case POSIXErrorDomain
    case OSStatusErrorDomain
    case DNSErrorDomain
    case NSCocoaErrorDomain
    case NSMachErrorDomain
    case NSStreamSOCKSErrorDomain
    case NSStreamSocketSSLErrorDomain
    case WSConnectionDomain
    case WSDataDomain
}

public struct WSError: Error, @unchecked Sendable {
    public let domain: WSErrorDomain
    public let code: WSErrorCode
    public let userInfo: [String: Any]
    
    public var description: String {
        var description = "\(domain) Error - \(codeString)"
        if !userInfo.isEmpty {
            description.append("\(userInfo)")
        }
        return description
    }
    
    public var codeString: String {
        switch self.code {
        case .invalidConnectionAccess:
            "Attempting to connect while connect is already running"
        case .socketNotConnected:
            "Socket is not connected"
        case .connectionNotReady:
            "Connection is not ready for data"
        case .failedToEncode:
            "Failed to encode the string as data"
        case .disconnectFailed:
            "Failed to disconnect the socket"
        case .connectFailed:
            "Failed to connect to the socket for an unknown reason"
        case .failedToDecode:
            "Failed to decode the received data"
        case .connectionTimedOut:
            "Failed to establish connection in time.  Edit this timeout value in `Socket.Options`."
        case .badDataFormat:
            "Received improperly formatted data."
        case .invalidHeartbeatInternval:
            "Invalid heartbeat interval - provide a value greater than or equal to 1.0 seconds."
        }
    }
    
    public init(domain: WSErrorDomain, code: WSErrorCode, userInfo: [String : Any] = [:]) {
        self.domain = domain
        self.code = code
        self.userInfo = userInfo
    }
}

public enum WSErrorDomain: String, Sendable {
    case WSConnectionDomain
    case WSDataDomain
}

public enum WSErrorCode: Int, Sendable {
    // MARK: - WSConnectionDomain
    case invalidConnectionAccess = 5001
    case socketNotConnected = 5002
    case connectionNotReady = 5003
    case disconnectFailed = 5004
    case connectFailed = 5005
    case connectionTimedOut = 5006
    
    // MARK: - WSDataDomain
    case failedToEncode = 5007
    case failedToDecode = 5008
    case badDataFormat = 5009
    case invalidHeartbeatInternval = 5010
}
