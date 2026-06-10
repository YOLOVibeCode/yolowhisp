import XCTest
@testable import YOLOWhisp

final class ModelDownloadTests: XCTestCase {
    func testAvailableRemoteModels() {
        let downloader = ModelDownloader()
        let models = downloader.availableRemoteModels()
        XCTAssertEqual(models.count, 6)
        XCTAssertTrue(models.contains("tiny"))
        XCTAssertTrue(models.contains("base"))
        XCTAssertTrue(models.contains("small"))
        XCTAssertTrue(models.contains("medium"))
        XCTAssertTrue(models.contains("large"))
        XCTAssertTrue(models.contains("large-v3-turbo"))
    }

    func testDownloadURLConstruction() {
        for model in ["tiny", "base", "small", "medium", "large"] {
            let url = ModelDownloader.downloadURL(for: model)
            XCTAssertEqual(url.absoluteString, "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-\(model).bin")
        }
    }

    func testInvalidModelThrows() async {
        let downloader = ModelDownloader()
        do {
            _ = try await downloader.download(model: "nonexistent", progress: { _ in })
            XCTFail("Expected invalidModel error")
        } catch let error as ModelDownloadError {
            if case .invalidModel(let name) = error {
                XCTAssertEqual(name, "nonexistent")
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDownloadReportsProgress() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        // Create 3MB of fake data so progress fires at least once
        let fakeData = Data(repeating: 0xAB, count: 3_000_000)
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Length": "\(fakeData.count)"]
            )!
            return (response, fakeData)
        }

        let downloader = ModelDownloader(session: session, destinationDirectory: tmpDir)
        var progressValues: [Double] = []

        let model = try await downloader.download(model: "tiny") { p in
            progressValues.append(p)
        }

        XCTAssertFalse(progressValues.isEmpty)
        XCTAssertEqual(progressValues.last, 1.0)
        XCTAssertEqual(model.name, "ggml-tiny")

        // Cleanup
        try? FileManager.default.removeItem(atPath: tmpDir)
    }

    func testDownloadWritesFile() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        let fakeData = Data(repeating: 0xFF, count: 512)
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Length": "\(fakeData.count)"]
            )!
            return (response, fakeData)
        }

        let downloader = ModelDownloader(session: session, destinationDirectory: tmpDir)
        let model = try await downloader.download(model: "base") { _ in }

        let expectedPath = "\(tmpDir)/ggml-base.bin"
        XCTAssertEqual(model.path, expectedPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedPath))
        XCTAssertEqual(model.size, 512)

        // Cleanup
        try? FileManager.default.removeItem(atPath: tmpDir)
    }

    func testCancelDownload() {
        let downloader = ModelDownloader()
        // Just verify it doesn't crash
        downloader.cancelDownload()
    }
}
