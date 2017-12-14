import Async
import Bits
import HTTP
import Foundation
import XCTest

class HTTPSerializerStreamTests: XCTestCase {
    func testResponse() throws {
        /// output and output request for later in test
        var output: [ByteBuffer] = []
        var outputRequest: OutputRequest?

        /// setup the mock app
        let mockApp = EmitterStream(HTTPResponse.self)
        mockApp.stream(to: HTTPResponseSerializer().stream()).drain(1) { buffer, req in
            output.append(buffer)
            outputRequest = req
        }.catch { err in
            XCTFail("\(err)")
        }.finally {
            // closed
        }

        /// sanity check
        XCTAssertEqual(output.count, 0)

        /// emit response
        let body = "<vapor>"
        let response = try HTTPResponse(
            status: .ok,
            body: body
        )
        mockApp.emit(response)

        /// there should only be one buffer since we
        /// called `.drain(1)`. this buffer should contain
        /// the entire response sans body
        XCTAssertEqual(output.count, 1)
        XCTAssertEqual(output.first?.count, 38)

        /// request another byte buffer
        outputRequest?.requestOutput(1)

        /// there should now be two outputted byte buffers
        /// with the second one being the entire body
        XCTAssertEqual(output.count, 2)
        XCTAssertEqual(output.last?.count, body.count)
    }

    func testResponseStreamingBody() throws {
        /// output and output request for later in test
        var output: [ByteBuffer] = []
        var outputRequest: OutputRequest?
        var closed = false

        /// setup the mock app
        let mockApp = EmitterStream(HTTPResponse.self)
        mockApp.stream(to: HTTPResponseSerializer().stream()).drain(1) { buffer, req in
            output.append(buffer)
            outputRequest = req
        }.catch { err in
            XCTFail("\(err)")
        }.finally {
            closed = true
        }

        /// sanity check
        XCTAssertEqual(output.count, 0)

        /// create a streaming body
        let bodyEmitter = EmitterStream(ByteBuffer.self)

        /// emit response
        let response = HTTPResponse(
            status: .ok,
            body: HTTPBody(chunked: bodyEmitter)
        )
        mockApp.emit(response)

        /// there should only be one buffer since we
        /// called `.drain(1)`. this buffer should contain
        /// the entire response sans body
        if output.count == 1 {
            let message = String(bytes: output[0], encoding: .utf8)
            XCTAssertEqual(message, "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n")
        } else {
            XCTFail("Invalid output count: \(output.count)")
        }

        /// request another byte buffer
        XCTAssertNotNil(outputRequest)

        /// the count should still be one, we are
        /// waiting on the body now
        XCTAssertEqual(output.count, 1)

        /// Request and emit additional output
        outputRequest?.requestOutput(1) // this must come before emit
        let a = "hello".data(using: .utf8)!
        a.withByteBuffer(bodyEmitter.emit)
        if output.count == 2 {
            let message = String(bytes: output[1], encoding: .utf8)
            XCTAssertEqual(message, "5\r\nhello\r\n")
        } else {
            XCTFail("Invalid output count: \(output.count)")
        }

        /// Request and emit additional output
        let b = "test".data(using: .utf8)!
        b.withByteBuffer(bodyEmitter.emit)
        outputRequest?.requestOutput(1)
        if output.count == 3 {
            let message = String(bytes: output[2], encoding: .utf8)
            XCTAssertEqual(message, "4\r\ntest\r\n")
        } else {
            XCTFail("Invalid output count: \(output.count)")
        }

        bodyEmitter.close()
        XCTAssertEqual(output.count, 3)
        outputRequest?.requestOutput(2)
        if output.count == 4 {
            let message = String(bytes: output[3], encoding: .utf8)
            XCTAssertEqual(message, "0\r\n\r\n")
        } else {
            XCTFail("Invalid output count: \(output.count)")
        }
        XCTAssertTrue(closed)
    }

    static let allTests = [
        ("testResponse", testResponse),
        ("testResponseStreamingBody", testResponseStreamingBody),
    ]
}
