import Foundation
@testable import OpenCastTranscription
import Testing

@Suite("OpenCast remote transcription models")
struct OpenCastRemoteModelTests {
    @Test("Remote manifest decodes gateway shape")
    func remoteManifestDecodesGatewayShape() throws {
        let data = Data(
            """
            {
              "schema_version": 1,
              "generated_at": "2026-06-28T00:00:00Z",
              "models": [
                {
                  "model_id": "openai_whisper-large-v3-v20240930_626MB",
                  "version": "20240930_626MB-v1",
                  "model_folder": "model",
                  "tokenizer_folder": "tokenizer",
                  "total_byte_count": 3,
                  "tree_sha256": "abc",
                  "files": [
                    {
                      "path": "model/config.json",
                      "url_path": "/v1/models/assets/openai_whisper-large-v3-v20240930_626MB/20240930_626MB-v1/model/config.json",
                      "byte_count": 3,
                      "sha256": "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
                      "content_type": "application/json; charset=utf-8"
                    }
                  ]
                }
              ]
            }
            """.utf8
        )

        let manifest = try JSONDecoder().decode(RemoteWhisperModelManifest.self, from: data)

        #expect(manifest.schemaVersion == 1)
        #expect(manifest.models[0].modelID == OpenCastWhisperModel.largeV3.rawValue)
        #expect(manifest.models[0].files[0].urlPath.hasPrefix("/v1/models/assets/"))
    }

    @Test("Downloaded locator rejects folders without an install receipt")
    func downloadedLocatorRejectsFoldersWithoutInstallReceipt() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "TranscriptionModels")
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        let installDirectory = root
            .appending(path: OpenCastWhisperModel.largeV3.rawValue)
            .appending(path: OpenCastWhisperModel.largeV3.defaultRemoteVersion)
        try FileManager.default.createDirectory(
            at: installDirectory.appending(path: "model"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: installDirectory.appending(path: "tokenizer"),
            withIntermediateDirectories: true
        )

        let locator = DownloadedWhisperModelLocator(
            installStore: OpenCastWhisperModelInstallStore(rootDirectory: root)
        )

        do {
            _ = try locator.modelLocation()
            Issue.record("Expected modelNotInstalled")
        } catch let error as OpenCastTranscriptionError {
            #expect(
                error == .modelNotInstalled(
                    modelIdentifier: OpenCastWhisperModel.largeV3.rawValue,
                    version: OpenCastWhisperModel.largeV3.defaultRemoteVersion
                )
            )
        } catch {
            Issue.record("Expected modelNotInstalled, got \(error)")
        }
    }

    @Test("Downloaded locator reports missing install")
    func downloadedLocatorReportsMissingInstall() {
        let locator = DownloadedWhisperModelLocator(
            installStore: OpenCastWhisperModelInstallStore(
                rootDirectory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            )
        )

        do {
            _ = try locator.modelLocation()
            Issue.record("Expected modelNotInstalled")
        } catch let error as OpenCastTranscriptionError {
            #expect(
                error == .modelNotInstalled(
                    modelIdentifier: OpenCastWhisperModel.largeV3.rawValue,
                    version: OpenCastWhisperModel.largeV3.defaultRemoteVersion
                )
            )
        } catch {
            Issue.record("Expected modelNotInstalled, got \(error)")
        }
    }

    @Test("SHA256 matches known digest")
    func sha256MatchesKnownDigest() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("txt")
        try Data("abc".utf8).write(to: url)
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        #expect(
            try OpenCastSHA256.hashFile(at: url)
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    @Test("SHA256 off-caller hashing respects cancellation")
    func sha256OffCallerHashingRespectsCancellation() async throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("txt")
        try Data("abc".utf8).write(to: url)
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let task = Task {
            try await OpenCastSHA256.hashFileOffCaller(at: url)
        }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    @Test("Source configuration builds explicit unescaped URLs")
    func sourceConfigurationBuildsExplicitUnescapedURLs() throws {
        let configuration = OpenCastRemoteModelGatewayConfiguration(
            baseURL: URL(string: "https://models.example.test/base?ignored=true")!
        )

        #expect(
            try configuration.assetURL(forPath: "/v1/models/assets/model/v1/model/config.json").absoluteString
                == "https://models.example.test/v1/models/assets/model/v1/model/config.json"
        )
        #expect(throws: OpenCastTranscriptionError.self) {
            _ = try configuration.assetURL(forPath: "v1/models/assets/model/v1/model/config.json")
        }
        #expect(throws: OpenCastTranscriptionError.self) {
            _ = try configuration.assetURL(forPath: "/v1/models/assets/model/v1/model/%63onfig.json")
        }
    }

    @Test("Pinned manifest is internally consistent")
    func pinnedManifestIsInternallyConsistent() async throws {
        let model = OpenCastPinnedWhisperModelManifest.largeV3

        #expect(model.modelID == OpenCastWhisperModel.largeV3.rawValue)
        #expect(model.version == OpenCastWhisperModel.largeV3.defaultRemoteVersion)
        #expect(OpenCastRemoteModelTreeHash.hash(files: model.files) == model.treeSHA256)
        #expect(model.files.reduce(0) { $0 + $1.byteCount } == model.totalByteCount)
        #expect(model.files.allSatisfy { $0.sha256.count == 64 })
        #expect(try await OpenCastWhisperModelInstaller().fetchManifest() == OpenCastPinnedWhisperModelManifest.current)
    }

    @Test("Pinned manifest downloads from commit-pinned Hugging Face paths")
    func pinnedManifestDownloadsFromCommitPinnedHuggingFacePaths() throws {
        let configuration = OpenCastRemoteModelGatewayConfiguration()
        let whisperKitPrefix = "https://huggingface.co/argmaxinc/whisperkit-coreml/resolve/"
            + OpenCastPinnedWhisperModelManifest.whisperKitRevision
            + "/openai_whisper-large-v3-v20240930_626MB/"
        let tokenizerPrefix = "https://huggingface.co/openai/whisper-large-v3/resolve/"
            + OpenCastPinnedWhisperModelManifest.tokenizerRevision + "/"

        #expect(OpenCastPinnedWhisperModelManifest.whisperKitRevision.count == 40)
        #expect(OpenCastPinnedWhisperModelManifest.tokenizerRevision.count == 40)
        for file in OpenCastPinnedWhisperModelManifest.largeV3.files {
            let url = try configuration.assetURL(forPath: file.urlPath).absoluteString
            if file.path.hasPrefix("model/") {
                #expect(url == whisperKitPrefix + file.path.dropFirst("model/".count))
            } else {
                #expect(url == tokenizerPrefix + file.path.dropFirst("tokenizer/".count))
            }
        }
    }

    @Test("Installer downloads fixture files and locator resolves receipt-backed install")
    func installerDownloadsFixtureFilesAndLocatorResolvesReceiptBackedInstall() async throws {
        let fixture = try RemoteModelFixture()
        let root = temporaryInstallRoot()
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        let installStore = OpenCastWhisperModelInstallStore(rootDirectory: root)
        let installer = OpenCastWhisperModelInstaller(
            configuration: fixture.configuration,
            installStore: installStore,
            limits: OpenCastWhisperModelInstallLimits(maximumFileByteCount: 1_024, maximumTotalByteCount: 2_048),
            transport: DictionaryRemoteModelTransport(downloadBodies: fixture.downloads)
        )

        let location = try await installer.install(manifest: fixture.manifest)
        let resolved = try DownloadedWhisperModelLocator(installStore: installStore).modelLocation()

        #expect(location.modelIdentifier == OpenCastWhisperModel.largeV3.rawValue)
        #expect(resolved.modelFolder == location.modelFolder)
        #expect(FileManager.default.fileExists(atPath: location.modelFolder.appending(path: "config.json").path))
        #expect(FileManager.default.fileExists(atPath: location.tokenizerFolder.appending(path: "tokenizer.json").path))
    }

    @Test("Installed summary requires a valid receipt-backed install")
    func installedSummaryRequiresValidReceiptBackedInstall() async throws {
        let fixture = try RemoteModelFixture()
        let root = temporaryInstallRoot()
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        let installStore = OpenCastWhisperModelInstallStore(rootDirectory: root)
        let installer = OpenCastWhisperModelInstaller(
            configuration: fixture.configuration,
            installStore: installStore,
            limits: OpenCastWhisperModelInstallLimits(maximumFileByteCount: 1_024, maximumTotalByteCount: 2_048),
            transport: DictionaryRemoteModelTransport(downloadBodies: fixture.downloads)
        )

        #expect(throws: OpenCastTranscriptionError.self) {
            _ = try installStore.installedSummary(
                modelIdentifier: fixture.model.modelID,
                version: fixture.model.version
            )
        }

        _ = try await installer.install(manifest: fixture.manifest)
        let summary = try installStore.installedSummary(
            modelIdentifier: fixture.model.modelID,
            version: fixture.model.version
        )

        #expect(summary.modelIdentifier == fixture.model.modelID)
        #expect(summary.version == fixture.model.version)
        #expect(summary.totalByteCount == fixture.model.totalByteCount)
        #expect(summary.treeSHA256 == fixture.model.treeSHA256)
    }

    @Test("Install directories are excluded from backup")
    func installDirectoriesAreExcludedFromBackup() throws {
        let root = temporaryInstallRoot()
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        let store = OpenCastWhisperModelInstallStore(rootDirectory: root)

        let stagingDirectory = try store.makeStagingDirectory()
        let rootValues = try root.resourceValues(forKeys: [.isExcludedFromBackupKey])
        let stagingValues = try stagingDirectory.resourceValues(forKeys: [.isExcludedFromBackupKey])

        #expect(rootValues.isExcludedFromBackup == true)
        #expect(stagingValues.isExcludedFromBackup == true)
    }

    @Test("Installer rejects corrupt fixture bytes")
    func installerRejectsCorruptFixtureBytes() async throws {
        let fixture = try RemoteModelFixture()
        var downloads = fixture.downloads
        let modelURL = try fixture.configuration.assetURL(forPath: fixture.model.files[0].urlPath)
        downloads[modelURL] = Data("wrong config".utf8)
        let installer = fixtureInstaller(fixture: fixture, downloads: downloads)

        do {
            _ = try await installer.install(manifest: fixture.manifest)
            Issue.record("Expected checksum mismatch")
        } catch OpenCastTranscriptionError.checksumMismatch {
        } catch {
            Issue.record("Expected checksum mismatch, got \(error)")
        }
    }

    @Test("Installer rejects wrong byte count")
    func installerRejectsWrongByteCount() async throws {
        let fixture = try RemoteModelFixture { model in
            model.files[0].byteCount += 1
            model.totalByteCount += 1
            model.treeSHA256 = OpenCastRemoteModelTreeHash.hash(files: model.files)
        }
        let installer = fixtureInstaller(fixture: fixture)

        do {
            _ = try await installer.install(manifest: fixture.manifest)
            Issue.record("Expected invalid manifest")
        } catch let error as OpenCastTranscriptionError {
            guard case .invalidRemoteManifest = error else {
                Issue.record("Expected invalidRemoteManifest, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected invalidRemoteManifest, got \(error)")
        }
    }

    @Test("Installer rejects bad file path")
    func installerRejectsBadFilePath() async throws {
        let fixture = try RemoteModelFixture { model in
            model.files[0].path = "model/../config.json"
            model.treeSHA256 = OpenCastRemoteModelTreeHash.hash(files: model.files)
        }
        let installer = fixtureInstaller(fixture: fixture)

        await expectInvalidManifest {
            _ = try await installer.install(manifest: fixture.manifest)
        }
    }

    @Test("Installer rejects bad tree hash")
    func installerRejectsBadTreeHash() async throws {
        let fixture = try RemoteModelFixture { model in
            model.treeSHA256 = String(repeating: "0", count: 64)
        }
        let installer = fixtureInstaller(fixture: fixture)

        await expectInvalidManifest {
            _ = try await installer.install(manifest: fixture.manifest)
        }
    }

    @Test(
        "Optional large-v3 pinned Hugging Face install probe",
        .enabled(if: ProcessInfo.processInfo.environment["OPENCAST_TRANSCRIPTION_INSTALL_LARGE_V3"] == "1")
    )
    func optionalLargeV3PinnedHuggingFaceInstallProbe() async throws {

        let installer = OpenCastWhisperModelInstaller()
        let start = ContinuousClock().now
        let location = try await installer.install { progress in
            print(
                "large-v3 install progress: \(progress.completedByteCount)/\(progress.totalByteCount) bytes, file \(progress.completedFileCount)/\(progress.totalFileCount)"
            )
        }
        let elapsed = start.duration(to: ContinuousClock().now).timeInterval
        let summary = try installer.installStore.installedSummary(
            modelIdentifier: OpenCastWhisperModel.largeV3.rawValue,
            version: OpenCastWhisperModel.largeV3.defaultRemoteVersion
        )

        print(
            "large-v3 install complete: model=\(location.modelIdentifier) bytes=\(summary.totalByteCount) tree=\(summary.treeSHA256) elapsed=\(elapsed)"
        )

        #expect(location.modelIdentifier == OpenCastWhisperModel.largeV3.rawValue)
        #expect(summary.totalByteCount > 0)
    }

    private func temporaryInstallRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "TranscriptionModels")
    }

    private func fixtureInstaller(
        fixture: RemoteModelFixture,
        downloads: [URL: Data]? = nil
    ) -> OpenCastWhisperModelInstaller {
        OpenCastWhisperModelInstaller(
            configuration: fixture.configuration,
            installStore: OpenCastWhisperModelInstallStore(rootDirectory: temporaryInstallRoot()),
            limits: OpenCastWhisperModelInstallLimits(maximumFileByteCount: 1_024, maximumTotalByteCount: 2_048),
            transport: DictionaryRemoteModelTransport(downloadBodies: downloads ?? fixture.downloads)
        )
    }

    private func expectInvalidManifest(
        _ operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            Issue.record("Expected invalid manifest")
        } catch let error as OpenCastTranscriptionError {
            guard case .invalidRemoteManifest = error else {
                Issue.record("Expected invalidRemoteManifest, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected invalidRemoteManifest, got \(error)")
        }
    }
}
