# AsyncSockets

🚧 WARNING 🚧
This is still a work in progress, and is not yet stable.

A modern Swift package providing an async/await WebSocket client implementation using Apple's Network framework. Built for Swift Concurrency, it offers a clean and type-safe API for WebSocket communications.

## Installation

### Swift Package Manager

Add AsyncSockets as a dependency to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/AsyncSockets.git", from: "1.0.0")
]
```

## Usage

### Basic Example

```swift
import AsyncSockets

// Initialize a socket with default options
let socket = Socket(host: "example.com", port: 8080)

// Connect to the server
try await socket.connect()

// Send a string message
try await socket.send("Hello, Server!")

// Receive a single message
let message = try await socket.receive()
print(message)

// Close the connection
try await socket.close()
```

### Working with Custom Types

AsyncSockets supports sending and receiving any `Codable` types:

```swift
struct ChatMessage: Codable, Sendable {
    let id: UUID
    let text: String
    let timestamp: Date
}

// Receive messages of a specific type
for try await message in socket.messages(ofType: ChatMessage.self) {
    print("Received: \(message.text)")
}
```

### Advanced Configuration

```swift
// Configure socket options
let options = Socket.Options(
    allowInsecureConnections: false,
    allowPathMigration: true
)

let socket = Socket(
    url: URL(string: "wss://example.com")!,
    options: options
)
```

### Async Sequence Support

AsyncSockets provides AsyncSequence support for continuous message handling:

```swift
// Handle all incoming messages
for try await message in socket.messages() {
    switch message {
    case .string(let text):
        print("Received text: \(text)")
    case .data(let data):
        print("Received data: \(data)")
    }
}
```

## Requirements

- Swift 5.5+
- iOS 13.0+ / macOS 10.15+
- Network.framework support

## License

This project is available under the MIT license. See the LICENSE file for more info. 
