import XCTest
@testable import YOLOWhisp

final class PostProcessingTests: XCTestCase {

    private func mockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func mockResponse(url: String, statusCode: Int = 200) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: url)!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    }

    // MARK: - Ollama

    func testOllamaRequestFormat() async throws {
        let config = PostProcessorConfig(
            providerType: .ollama, modelName: "llama3",
            endpoint: "http://localhost:11434/api/generate"
        )
        let session = mockSession()
        let provider = OllamaProvider(config: config, session: session)

        MockURLProtocol.requestHandler = { request in
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            XCTAssertEqual(body["model"] as? String, "llama3")
            XCTAssertEqual(body["stream"] as? Bool, false)
            XCTAssertNotNil(body["prompt"] as? String)
            XCTAssertEqual(request.httpMethod, "POST")

            let responseData = try JSONSerialization.data(withJSONObject: ["response": "ok"])
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, responseData)
        }

        _ = try await provider.process(text: "hello world")
    }

    func testOllamaResponseParsing() async throws {
        let config = PostProcessorConfig(
            providerType: .ollama, modelName: "llama3",
            endpoint: "http://localhost:11434/api/generate"
        )
        let session = mockSession()
        let provider = OllamaProvider(config: config, session: session)

        MockURLProtocol.requestHandler = { request in
            let data = try JSONSerialization.data(withJSONObject: ["response": "Fixed text."])
            return (self.mockResponse(url: "http://localhost:11434/api/generate"), data)
        }

        let result = try await provider.process(text: "fixd txt")
        XCTAssertEqual(result, "Fixed text.")
    }

    // MARK: - OpenAI

    func testOpenAIRequestFormat() async throws {
        let config = PostProcessorConfig(
            providerType: .openai, modelName: "gpt-4",
            endpoint: "https://api.openai.com/v1/chat/completions",
            apiKey: "sk-test-key"
        )
        let session = mockSession()
        let provider = OpenAIProvider(config: config, session: session)

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test-key")
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            let messages = body["messages"] as! [[String: String]]
            XCTAssertEqual(messages.count, 2)
            XCTAssertEqual(messages[0]["role"], "system")
            XCTAssertEqual(messages[1]["role"], "user")

            let responseJSON: [String: Any] = [
                "choices": [["message": ["content": "Done"]]]
            ]
            let data = try JSONSerialization.data(withJSONObject: responseJSON)
            return (self.mockResponse(url: "https://api.openai.com/v1/chat/completions"), data)
        }

        _ = try await provider.process(text: "test")
    }

    func testOpenAIResponseParsing() async throws {
        let config = PostProcessorConfig(
            providerType: .openai, modelName: "gpt-4",
            endpoint: "https://api.openai.com/v1/chat/completions",
            apiKey: "sk-test"
        )
        let session = mockSession()
        let provider = OpenAIProvider(config: config, session: session)

        MockURLProtocol.requestHandler = { request in
            let responseJSON: [String: Any] = [
                "choices": [["message": ["content": "Polished output."]]]
            ]
            let data = try JSONSerialization.data(withJSONObject: responseJSON)
            return (self.mockResponse(url: "https://api.openai.com/v1/chat/completions"), data)
        }

        let result = try await provider.process(text: "raw input")
        XCTAssertEqual(result, "Polished output.")
    }

    // MARK: - Anthropic

    func testAnthropicRequestFormat() async throws {
        let config = PostProcessorConfig(
            providerType: .anthropic, modelName: "claude-3-sonnet",
            endpoint: "https://api.anthropic.com/v1/messages",
            apiKey: "ant-key"
        )
        let session = mockSession()
        let provider = AnthropicProvider(config: config, session: session)

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "ant-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")

            let responseJSON: [String: Any] = [
                "content": [["type": "text", "text": "Done"]]
            ]
            let data = try JSONSerialization.data(withJSONObject: responseJSON)
            return (self.mockResponse(url: "https://api.anthropic.com/v1/messages"), data)
        }

        _ = try await provider.process(text: "test")
    }

    func testAnthropicResponseParsing() async throws {
        let config = PostProcessorConfig(
            providerType: .anthropic, modelName: "claude-3-sonnet",
            endpoint: "https://api.anthropic.com/v1/messages",
            apiKey: "ant-key"
        )
        let session = mockSession()
        let provider = AnthropicProvider(config: config, session: session)

        MockURLProtocol.requestHandler = { request in
            let responseJSON: [String: Any] = [
                "content": [["type": "text", "text": "Corrected text."]]
            ]
            let data = try JSONSerialization.data(withJSONObject: responseJSON)
            return (self.mockResponse(url: "https://api.anthropic.com/v1/messages"), data)
        }

        let result = try await provider.process(text: "input")
        XCTAssertEqual(result, "Corrected text.")
    }

    // MARK: - Custom

    func testCustomProviderUsesEndpoint() async throws {
        let config = PostProcessorConfig(
            providerType: .custom, modelName: "custom-model",
            endpoint: "https://my-api.example.com/process"
        )
        let session = mockSession()
        let provider = CustomProvider(config: config, session: session)

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://my-api.example.com/process")
            let data = try JSONSerialization.data(withJSONObject: ["result": "Custom result"])
            return (self.mockResponse(url: "https://my-api.example.com/process"), data)
        }

        let result = try await provider.process(text: "input")
        XCTAssertEqual(result, "Custom result")
    }

    // MARK: - Error cases

    func testNetworkErrorThrows() async throws {
        let config = PostProcessorConfig(
            providerType: .ollama, modelName: "llama3",
            endpoint: "http://localhost:11434/api/generate"
        )
        let session = mockSession()
        let provider = OllamaProvider(config: config, session: session)

        MockURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        do {
            _ = try await provider.process(text: "test")
            XCTFail("Expected error")
        } catch {
            // Network error thrown — pass
            XCTAssertFalse(error is PostProcessError && {
                if case .invalidResponse = error as! PostProcessError { return true }
                return false
            }())
        }
    }

    func testInvalidResponseThrows() async throws {
        let config = PostProcessorConfig(
            providerType: .ollama, modelName: "llama3",
            endpoint: "http://localhost:11434/api/generate"
        )
        let session = mockSession()
        let provider = OllamaProvider(config: config, session: session)

        MockURLProtocol.requestHandler = { request in
            let data = Data("not json at all {garbage".utf8)
            return (self.mockResponse(url: "http://localhost:11434/api/generate"), data)
        }

        do {
            _ = try await provider.process(text: "test")
            XCTFail("Expected PostProcessError.invalidResponse")
        } catch let error as PostProcessError {
            if case .invalidResponse = error {
                // pass
            } else {
                XCTFail("Expected .invalidResponse, got \(error)")
            }
        }
    }
}
