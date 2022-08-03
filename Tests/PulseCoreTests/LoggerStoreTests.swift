// The MIT License (MIT)
//
// Copyright (c) 2020-2022 Alexander Grebenyuk (github.com/kean).

import XCTest
import Foundation
import CoreData
@testable import PulseCore

final class LoggerStoreTests: XCTestCase {
    let directory = TemporaryDirectory()
    var tempDirectoryURL: URL!
    var storeURL: URL!
    var date: Date = Date()

    var store: LoggerStore!

    override func setUp() {
        super.setUp()

        tempDirectoryURL = FileManager().temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true, attributes: [:])
        storeURL = tempDirectoryURL.appendingPathComponent("test-store")

        store = try! LoggerStore(storeURL: storeURL, options: [.create, .synchronous])
    }

    override func tearDown() {
        super.tearDown()

        directory.remove()

        store.destroyStores()

        try? FileManager.default.removeItem(at: tempDirectoryURL)
        try? FileManager.default.removeItem(at: URL.temp)
        try? FileManager.default.removeItem(at: URL.logs)
    }

    // MARK: - Init

    func testInitStoreMissing() throws {
        // GIVEN
        let storeURL = tempDirectoryURL.appendingPathComponent(UUID().uuidString)

        // WHEN/THEN
        XCTAssertThrowsError(try LoggerStore(storeURL: storeURL))
    }

    func testInitCreateStoreURL() throws {
        // GIVEN
        let storeURL = tempDirectoryURL.appendingPathComponent(UUID().uuidString)
        let options: LoggerStore.Options = [.create]

        // WHEN
        let firstStore = try LoggerStore(storeURL: storeURL, options: options)
        try firstStore.populate()

        let secondStore = try LoggerStore(storeURL: storeURL)

        // THEN data is persisted
        XCTAssertEqual(try secondStore.allMessages().count, 1)

        // CLEANUP
        firstStore.destroyStores()
        secondStore.destroyStores()
    }

    func testInitCreateStoreIntermediateDirectoryMissing() throws {
        // GIVEN
        let storeURL = tempDirectoryURL
            .appendingPathComponent(UUID().uuidString, isDirectory: false) // Missing directory
            .appendingPathComponent(UUID().uuidString)
        let options: LoggerStore.Options = [.create]

        // WHEN/THEN
        XCTAssertThrowsError(try LoggerStore(storeURL: storeURL, options: options))
    }

    func testInitStoreWithURL() throws {
        // GIVEN
        try store.populate()
        XCTAssertEqual(try store.allMessages().count, 1)

        let originalStore = store
        store.removeStores()

        // WHEN loading the store with the same url
        store = try LoggerStore(storeURL: storeURL)

        // THEN data is persisted
        XCTAssertEqual(try store.allMessages().count, 1)

        // CLEANUP
        originalStore?.destroyStores()
    }

    func testInitWithArchiveURL() throws {
        // GIVEN
        let storeURL = tempDirectoryURL.appendingPathComponent("logs-2021-03-18_21-22.pulse")
        try Resources.pulseArchive.write(to: storeURL)

        // WHEN
        let store = try XCTUnwrap(LoggerStore(storeURL: storeURL))
        defer { store.destroyStores() }

        // THEN
        XCTAssertEqual(try store.allMessages().count, 23)
        XCTAssertEqual(try store.allNetworkRequests().count, 4)
    }

    func testInitWithArchiveURLNoExtension() throws {
        // GIVEN
        let storeURL = tempDirectoryURL.appendingPathComponent("logs-2021-03-18_21-22")
        try Resources.pulseArchive.write(to: storeURL)

        // WHEN
        let store = try XCTUnwrap(LoggerStore(storeURL: storeURL))
        defer { store.destroyStores() }

        // THEN
        XCTAssertEqual(try store.allMessages().count, 23)
        XCTAssertEqual(try store.allNetworkRequests().count, 4)
    }

    func testInitWithPackageURL() throws {
        // GIVEN
        let archiveURL = tempDirectoryURL.appendingPathComponent(UUID().uuidString)
        try Resources.pulsePackage.write(to: archiveURL)
        try FileManager.default.unzipItem(at: archiveURL, to: tempDirectoryURL)
        let storeURL = tempDirectoryURL.appendingPathComponent("logs-package.pulse")

        // WHEN
        let store = try XCTUnwrap(LoggerStore(storeURL: storeURL))
        defer { store.destroyStores() }

        // THEN
        XCTAssertEqual(try store.allMessages().count, 23)
        XCTAssertEqual(try store.allNetworkRequests().count, 4)
    }

    func testInitWithPackageURLNoExtension() throws {
        // GIVEN
        let archiveURL = tempDirectoryURL.appendingPathComponent(UUID().uuidString)
        try Resources.pulsePackage.write(to: archiveURL)
        try FileManager.default.unzipItem(at: archiveURL, to: tempDirectoryURL)
        let originalURL = tempDirectoryURL.appendingPathComponent("logs-package.pulse")

        let storeURL = tempDirectoryURL.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: originalURL, to: storeURL)

        // WHEN
        let store = try XCTUnwrap(LoggerStore(storeURL: storeURL))
        defer { store.destroyStores() }

        // THEN
        XCTAssertEqual(try store.allMessages().count, 23)
        XCTAssertEqual(try store.allNetworkRequests().count, 4)
    }

    // MARK: - Copy (Directory)

    func testCopyDirectory() throws {
        // GIVEN
        populate2(store: store)

        let copyURL = tempDirectoryURL.appendingPathComponent("copy.pulse")

        // WHEN
        let manifest = try store.copy(to: copyURL)

        // THEN
        // XCTAssertEqual(manifest.messagesSize, 73728)
        // XCTAssertEqual(manifest.blobsSize, 21195)
        XCTAssertEqual(manifest.messageCount, 10)
        XCTAssertEqual(manifest.requestCount, 3)

        store.removeStores()

        // THEN
        let copy = try LoggerStore(storeURL: copyURL)
        defer { copy.destroyStores() }

        XCTAssertEqual(try copy.allMessages().count, 10)
        XCTAssertEqual(try copy.allNetworkRequests().count, 3)
    }

    func testCopyToNonExistingFolder() throws {
        // GIVEN
        populate2(store: store)

        let invalidURL = tempDirectoryURL
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("copy.pulse")

        // WHEN/THEN
        XCTAssertThrowsError(try store.copy(to: invalidURL))
    }

    func testCopyButFileExists() throws {
        // GIVEN
        populate2(store: store)

        let copyURL = tempDirectoryURL
            .appendingPathComponent("copy.pulse")

        try store.copy(to: copyURL)

        // WHEN/THEN
        XCTAssertThrowsError(try store.copy(to: copyURL))
    }

    func testCreateMultipleCopies() throws {
        // GIVEN
        populate2(store: store)

        let copyURL1 = self.storeURL
            .deletingLastPathComponent()
            .appendingPathComponent("copy.pulse")

        let copyURL2 = self.storeURL
            .deletingLastPathComponent()
            .appendingPathComponent("copy2.pulse")

        // WHEN
        let manifest1 = try store.copy(to: copyURL1)
        let manifest2 = try store.copy(to: copyURL2)

        // THEN
        // XCTAssertEqual(manifest.messagesSize, 73728)
        // XCTAssertEqual(manifest.blobsSize, 21195)
        XCTAssertEqual(manifest1.messageCount, 10)
        XCTAssertEqual(manifest1.requestCount, 3)
        XCTAssertEqual(manifest2.messageCount, 10)
        XCTAssertEqual(manifest2.requestCount, 3)
        XCTAssertNotEqual(manifest1.id, manifest2.id)
    }

    // MARK: - Copy (File)

    func testCopyFile() throws {
        // GIVEN
        let storeURL = directory.url.appendingPathComponent("logs-2021-03-18_21-22.pulse")
        try Resources.pulseArchive.write(to: storeURL)

        let store = try XCTUnwrap(LoggerStore(storeURL: storeURL))
        let copyURL = tempDirectoryURL.appendingPathComponent("copy.pulse")

        // WHEN
        let manifest = try store.copy(to: copyURL)

        // THEN
        // XCTAssertEqual(manifest.messagesSize, 73728)
        // XCTAssertEqual(manifest.blobsSize, 21195)
        XCTAssertEqual(manifest.messageCount, 23)
        XCTAssertEqual(manifest.requestCount, 4)

        // THEN
        let copy = try LoggerStore(storeURL: copyURL)
        defer { copy.destroyStores() }

        XCTAssertEqual(try copy.allMessages().count, 23)
        XCTAssertEqual(try copy.allNetworkRequests().count, 4)
    }

    // MARK: - File (Readonly)

    // TODO: this type of store is no longer immuatble
    func _testOpenFileDatabaseImmutable() throws {
        // GIVEN
        let storeURL = directory.url.appendingPathComponent("logs-2021-03-18_21-22.pulse")
        try Resources.pulseArchive.write(to: storeURL)

        let store = try XCTUnwrap(LoggerStore(storeURL: storeURL))
        XCTAssertEqual(try store.allMessages().count, 23)

        // WHEN/THEN
        store.storeMessage(label: "test", level: .info, message: "test", metadata: nil)

        // THEN nothing is written
        XCTAssertEqual(try store.allMessages().count, 23)

        let storeCopy = try XCTUnwrap(LoggerStore(storeURL: storeURL))
        XCTAssertEqual(try storeCopy.allMessages().count, 23)
    }

    // MARK: - Expiration

    func testSizeLimit() throws {
        let store = try! LoggerStore(
            storeURL: directory.url.appendingPathComponent(UUID().uuidString),
            options: [.create, .synchronous],
            configuration: .init(databaseSizeLimit: 5000)
        )
        defer { store.destroyStores() }

        // GIVEN
        let context = store.viewContext

        for index in 1...500 {
            store.storeMessage(label: "default", level: .debug, message: "\(index)", metadata: {
                index % 50 == 0 ? ["key": .stringConvertible(index)] : nil
            }())
        }

        let copyURL = tempDirectoryURL
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("pulse")
        try store.copy(to: copyURL)

        // SANITY
        var messages = try store.allMessages()
        XCTAssertEqual(messages.count, 500)
        XCTAssertEqual(messages.last?.text, "500")

        XCTAssertEqual(try context.fetch(LoggerMessageEntity.fetchRequest()).count, 500)
        XCTAssertEqual(try context.fetch(LoggerMetadataEntity.fetchRequest()).count, 10)

        // WHEN
        store.syncSweep()

        // THEN
        let copyURL2 = tempDirectoryURL
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("pulse")
        try store.copy(to: copyURL2)

        // THEN unwanted messages were removed
        messages = try store.allMessages()
        XCTAssertEqual(messages.count, 251)
        XCTAssertEqual(messages.last?.text, "500") // Latest stored

        // THEN metadata and other relationships also removed
        XCTAssertEqual(try context.fetch(LoggerMessageEntity.fetchRequest()).count, 251)
        XCTAssertEqual(try context.fetch(LoggerMetadataEntity.fetchRequest()).count, 6)
    }

    func testMaxAgeSweep() throws {
        // GIVEN the store with 5 minute max age
        let store = makeStore {
            $0.maxAge = 300
        }
        defer { store.destroyStores() }

        // GIVEN some messages stored before the cutoff date
        date = Date().addingTimeInterval(-1000)
        store.storeMessage(label: "deleted", level: .debug, message: "test")
        store.storeRequest(URLRequest(url: URL(string: "example.com/deleted")!), response: nil, error: nil, data: nil)

        // GIVEN some messages stored after
        date = Date()
        store.storeMessage(label: "kept", level: .debug, message: "test")
        store.storeRequest(URLRequest(url: URL(string: "example.com/kept")!), response: nil, error: nil, data: nil)

        // ASSERT
        let context = store.backgroundContext
        XCTAssertEqual(try context.fetch(LoggerMessageEntity.fetchRequest()).count, 4)
        XCTAssertEqual(try context.fetch(LoggerNetworkRequestEntity.fetchRequest()).count, 2)
        XCTAssertEqual(try context.fetch(LoggerNetworkRequestDetailsEntity.fetchRequest()).count, 2)
        XCTAssertEqual(try context.fetch(LoggerBlobHandleEntity.fetchRequest()).count, 0)

        // WHEN
        store.syncSweep()

        // THEN
        XCTAssertEqual(try context.fetch(LoggerMessageEntity.fetchRequest()).count, 2)
        XCTAssertEqual(try context.fetch(LoggerMetadataEntity.fetchRequest()).count, 0)
        XCTAssertEqual(try context.fetch(LoggerNetworkRequestEntity.fetchRequest()).count, 1)
        XCTAssertEqual(try context.fetch(LoggerNetworkRequestDetailsEntity.fetchRequest()).count, 1)
        XCTAssertEqual(try context.fetch(LoggerNetworkRequestProgressEntity.fetchRequest()).count, 0)
        XCTAssertEqual(try context.fetch(LoggerBlobHandleEntity.fetchRequest()).count, 0)

        XCTAssertEqual(try store.allMessages().first?.label, "kept")
        XCTAssertEqual(try store.allNetworkRequests().first?.url, "example.com/kept")
    }

    func testMaxAgeSweepBlobIsDeletedWhenEntityIsDeleted() throws {
        // GIVEN the store with 5 minute max age
        let store = makeStore {
            $0.maxAge = 300
        }
        defer { store.destroyStores() }

        // GIVEN a request with response body stored
        date = Date().addingTimeInterval(-1000)
        let responseData = "body".data(using: .utf8)!
        store.storeRequest(URLRequest(url: URL(string: "example.com/deleted")!), response: nil, error: nil, data: responseData)

        // ASSERT
        let responseBodyKey = try XCTUnwrap(store.allNetworkRequests().first?.responseBodyKey)
        XCTAssertEqual(store.getData(forKey: responseBodyKey), responseData)

        XCTAssertEqual(try store.backgroundContext.fetch(LoggerBlobHandleEntity.fetchRequest()).count, 1)

        // WHEN
        date = Date()
        store.syncSweep()

        // THEN associated data is deleted
        XCTAssertEqual(try store.backgroundContext.fetch(LoggerBlobHandleEntity.fetchRequest()).count, 0)
        XCTAssertNil(store.getData(forKey: responseBodyKey))
    }

    func testMaxAgeSweepBlobIsDeletedWhenBothEntitiesReferencingItAre() throws {
        // GIVEN the store with 5 minute max age
        let store = makeStore {
            $0.maxAge = 300
        }
        defer { store.destroyStores() }

        // GIVEN a request with response body stored
        date = Date().addingTimeInterval(-1000)
        let responseData = "body".data(using: .utf8)!
        store.storeRequest(URLRequest(url: URL(string: "example.com/deleted1")!), response: nil, error: nil, data: responseData)
        store.storeRequest(URLRequest(url: URL(string: "example.com/deleted2")!), response: nil, error: nil, data: responseData)

        // ASSERT
        let responseBodyKey = try XCTUnwrap(store.backgroundContext.fetch(LoggerNetworkRequestEntity.self).first?.responseBody?.key)
        XCTAssertEqual(store.getData(forKey: responseBodyKey), responseData)
        XCTAssertEqual(try store.backgroundContext.fetch(LoggerBlobHandleEntity.fetchRequest()).count, 1)

        // WHEN
        date = Date()
        store.syncSweep()

        // THEN associated data is deleted
        XCTAssertEqual(try store.backgroundContext.fetch(LoggerBlobHandleEntity.fetchRequest()).count, 0)
        XCTAssertNil(store.getData(forKey: responseBodyKey))
    }

    func testMaxAgeSweepBlobIsKeptIfOnlyOneReferencingEntityIsDeleted() throws {
        // GIVEN the store with 5 minute max age
        let store = makeStore {
            $0.maxAge = 300
        }
        defer { store.destroyStores() }

        // GIVEN a request with response body stored
        date = Date().addingTimeInterval(-1000)
        let responseData = "body".data(using: .utf8)!
        store.storeRequest(URLRequest(url: URL(string: "example.com/deleted")!), response: nil, error: nil, data: responseData)

        // GIVEN a request that's not deleted
        date = Date()
        store.storeRequest(URLRequest(url: URL(string: "example.com/kept")!), response: nil, error: nil, data: responseData)

        // ASSERT
        let responseBodyKey = try XCTUnwrap(store.backgroundContext.fetch(LoggerNetworkRequestEntity.self).first?.responseBody?.key)
        XCTAssertEqual(store.getData(forKey: responseBodyKey), responseData)
        XCTAssertEqual(try store.backgroundContext.fetch(LoggerNetworkRequestEntity.fetchRequest()).count, 2)
        XCTAssertEqual(try store.backgroundContext.fetch(LoggerBlobHandleEntity.fetchRequest()).count, 1)

        // WHEN
        date = Date()
        store.syncSweep()

        // THEN associated data is deleted
        XCTAssertEqual(try store.backgroundContext.fetch(LoggerNetworkRequestEntity.fetchRequest()).count, 1)
        XCTAssertEqual(try store.backgroundContext.fetch(LoggerBlobHandleEntity.fetchRequest()).count, 1)
        XCTAssertEqual(store.getData(forKey: responseBodyKey), responseData)
    }

    func testBlobSizeLimitSweep() throws {
        // GIVEN store with blob size limit
        let store = makeStore {
            $0.maxAge = 300
            $0.blobsSizeLimit = 700 // will trigger sweep
            $0.trimRatio = 0.5 // will remove items until 350 bytes are used
        }

        let now = Date()

        func storeRequest(id: String, offset: TimeInterval) {
            date = now.addingTimeInterval(offset)
            // Make sure data doesn't get deduplicated
            let data = Data(count: 300) + id.data(using: .utf8)!

            store.storeRequest(URLRequest(url: URL(string: "example.com/\(id)")!), response: nil, error: nil, data: data)
        }

        storeRequest(id: "1", offset: -100)
        storeRequest(id: "2", offset: 0)
        storeRequest(id: "3", offset: -200)

        // ASSERT
        let responseBodyKeys = try store.backgroundContext.fetch(LoggerNetworkRequestEntity.self).compactMap { $0.responseBodyKey }
        XCTAssertEqual(try store.backgroundContext.fetch(LoggerBlobHandleEntity.self).count, 3)
        XCTAssertEqual(responseBodyKeys.compactMap(store.getData).count, 3)

        // WHEN
        store.syncSweep()

        // THEN
        let requests = try store.backgroundContext.fetch(LoggerNetworkRequestEntity.self)
        XCTAssertEqual(requests.count, 3) // Keeps the requests
        XCTAssertEqual(requests.compactMap(\.responseBody).count, 1)
        XCTAssertEqual(try store.backgroundContext.fetch(LoggerBlobHandleEntity.self).count, 1)
        XCTAssertEqual(responseBodyKeys.compactMap(store.getData(forKey:)).count, 1)
    }

    // MARK: - Migration

    func testMigrationFromVersion0_2ToLatest() throws {
        // GIVEN store created with the model from Pulse 0.2
        let storeURL = tempDirectoryURL
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try? FileManager.default.createDirectory(at: storeURL, withIntermediateDirectories: true, attributes: nil)
        let databaseURL = storeURL
            .appendingPathComponent("logs.sqlite", isDirectory: false)
        try Resources.outdatedDatabase.write(to: databaseURL)

        // WHEN migrating to the store with the latest model
        let store = try LoggerStore(storeURL: storeURL, options: [.synchronous])
        defer { store.destroyStores() }

        // THEN automatic migration is performed and new field are populated with
        // empty values
        let messages = try store.allMessages()
        XCTAssertEqual(messages.count, 0, "Previously recorded messages are going to be lost")

        // WHEN
        try store.populate()

        // THEN can write new messages
        XCTAssertEqual(try store.allMessages().count, 1)
    }

    // MARK: - Remove Messages

    #warning("TODO: add blobs tests")
    func testRemoveAllMessages() throws {
        // GIVEN
        populate2(store: store)
        store.storeMessage(label: "with meta", level: .debug, message: "test", metadata: ["hey": .string("this is meta yo")], file: #file, function: #function, line: #line)

        let context = store.viewContext
        XCTAssertEqual(try context.fetch(LoggerMessageEntity.self).count, 11)
        XCTAssertEqual(try context.fetch(LoggerMetadataEntity.self).count, 1)
        XCTAssertEqual(try context.fetch(LoggerNetworkRequestEntity.self).count, 3)
        XCTAssertEqual(try context.fetch(LoggerNetworkRequestDetailsEntity.self).count, 3)

        // WHEN
        store.removeAll()

        // THEN both message and metadata are removed
        XCTAssertTrue(try context.fetch(LoggerMessageEntity.self).isEmpty)
        XCTAssertTrue(try context.fetch(LoggerMetadataEntity.self).isEmpty)
        XCTAssertTrue(try context.fetch(LoggerNetworkRequestEntity.self).isEmpty)
        XCTAssertTrue(try context.fetch(LoggerNetworkRequestDetailsEntity.self).isEmpty)
    }

    // MARK: - Image Support

#if os(iOS)
    func testImageThumbnailsAreStored() throws {
        // GIVEN
        let image = try makeMockImage()
        XCTAssertEqual(image.size, CGSize(width: 2048, height: 2048))
        let imageData = try XCTUnwrap(image.pngData())

        // WHEN
        let url = try XCTUnwrap(URL(string: "https://example.com/image"))
        let taskId = UUID()

        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "http/2.0", headerFields: [
            "Content-Type": "image/png"
        ])

        store.storeRequest(taskId: taskId, taskType: .dataTask, request: URLRequest(url: url), response: response, error: nil, data: imageData, metrics: nil)

        // THEN
        let request = try XCTUnwrap(store.allNetworkRequests().first(where: { $0.taskId == taskId }))
        let responseBodyKey = try XCTUnwrap(request.responseBodyKey)
        let processedData = try XCTUnwrap(store.getData(forKey: responseBodyKey))
        let thumbnail = try XCTUnwrap(UIImage(data: processedData))
        XCTAssertEqual(thumbnail.size, CGSize(width: 256, height: 256))

        // THEN original image size saved
        let metadata = try XCTUnwrap(JSONDecoder().decode([String: String].self, from: request.details.metadata ?? Data()))
        XCTAssertEqual(metadata["ResponsePixelWidth"].flatMap { Int($0) }, 2048)
        XCTAssertEqual(metadata["ResponsePixelHeight"].flatMap { Int($0) }, 2048)
    }

    private func makeMockImage() throws -> UIImage {
        UIGraphicsBeginImageContextWithOptions(CGSize(width: 2048, height: 2048), true, 1)
        let context = try XCTUnwrap(UIGraphicsGetCurrentContext())

        UIColor.red.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 2048, height: 2048))

        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return try XCTUnwrap(image)
    }
#endif

    // MARK: - Helpers

    private func makeStore(_ closure: (inout LoggerStore.Configuration) -> Void) -> LoggerStore {
        var configuration = LoggerStore.Configuration()
        configuration.makeCurrentDate = { [unowned self] in self.date }
        closure(&configuration)

        return try! LoggerStore(
            storeURL: directory.url.appendingPathComponent(UUID().uuidString),
            options: [.create, .synchronous],
            configuration: configuration
        )
    }
}

private extension LoggerStore {
    func populate() throws {
        storeMessage(label: "default", level: .debug, message: "Some message", metadata: [
            "system": .string("application")
        ])
    }
}
