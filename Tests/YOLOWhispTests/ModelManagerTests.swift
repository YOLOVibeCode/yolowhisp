import XCTest
@testable import YOLOWhisp

final class ModelManagerTests: XCTestCase {
    func testConformsToProtocol() {
        let manager: any ModelManaging = ModelManager()
        XCTAssertNotNil(manager)
    }

    func testCurrentModel() {
        let manager = ModelManager()
        XCTAssertNil(manager.currentModel)
    }

    func testScanFindsModelsInDirectory() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        // Create fake model files
        FileManager.default.createFile(atPath: (tmpDir as NSString).appendingPathComponent("ggml-base.bin"), contents: Data([0x00, 0x01]))
        FileManager.default.createFile(atPath: (tmpDir as NSString).appendingPathComponent("ggml-small.bin"), contents: Data([0x00, 0x01, 0x02]))
        // Non-matching file
        FileManager.default.createFile(atPath: (tmpDir as NSString).appendingPathComponent("other.txt"), contents: Data())

        let manager = ModelManager(searchPaths: [tmpDir])
        let models = manager.availableModels()

        XCTAssertEqual(models.count, 2)
        let names = models.map(\.name).sorted()
        XCTAssertEqual(names, ["base", "small"])
    }

    func testLoadNonExistentPathThrows() {
        let manager = ModelManager()
        let model = WhisperModel(name: "fake", path: "/nonexistent/ggml-fake.bin", size: 100)

        XCTAssertThrowsError(try manager.loadModel(model)) { error in
            XCTAssertEqual(error as? ModelManagerError, .modelNotFound("/nonexistent/ggml-fake.bin"))
        }
    }

    func testAvailableModelsReturnsFileSize() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let data = Data(repeating: 0xAB, count: 1024)
        FileManager.default.createFile(atPath: (tmpDir as NSString).appendingPathComponent("ggml-tiny.bin"), contents: data)

        let manager = ModelManager(searchPaths: [tmpDir])
        let models = manager.availableModels()

        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models[0].size, 1024)
    }

    func testScanEmptyDirectoryReturnsEmpty() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let manager = ModelManager(searchPaths: [tmpDir])
        XCTAssertEqual(manager.availableModels(), [])
    }
}
