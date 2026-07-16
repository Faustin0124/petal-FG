import AVFoundation
import Dependencies
import DependenciesMacros
import Foundation
import AudioSpeedClient
import AudioTrimClient
import LogClient
import MLXClient
import Shared
#if canImport(Speech)
import Speech
#endif

/// A live, incremental transcription session. `pushBuffer` feeds live microphone audio in as it's
/// captured; `partialResultHandler` (passed to `TranscriptionClient.startStreaming`) is invoked with
/// the best-effort transcript so far each time it changes. `finish` stops capture, finalizes any
/// pending (volatile) results, and returns the complete transcript — analogous to `transcribe(...)`'s
/// return value for the batch path.
public struct StreamingTranscriptionHandle: Sendable {
    public var pushBuffer: @Sendable (AVAudioPCMBuffer) -> Void
    public var finish: @Sendable () async throws -> String
    public var cancel: @Sendable () -> Void
}

public enum TranscriptionStreamingError: LocalizedError, Sendable {
    /// Streaming is currently only implemented for Apple Speech (`SpeechAnalyzer` natively
    /// streams). Other backends (FluidAudio, WhisperKit, Voxtral MLX) fall back to the batch
    /// `transcribe(...)` path until a verified streaming integration is added for them.
    case unsupported(ModelOption)

    public var errorDescription: String? {
        switch self {
        case let .unsupported(option):
            return "\(option.rawValue) does not support streaming transcription yet."
        }
    }
}

@DependencyClient
public struct TranscriptionClient: Sendable {
    public var prepareModelIfNeeded: @Sendable (ModelOption) async throws -> Void
    public var transcribe: @Sendable (URL, ModelOption, TranscriptionMode, String?, String?, String?) async throws -> String
    /// Starts a live streaming transcription session for `option`, if supported (see
    /// `TranscriptionStreamingError.unsupported`). Feed audio via the returned handle's
    /// `pushBuffer`, observe live text via `partialResultHandler`, and call `finish` when
    /// recording stops to get the final transcript.
    public var startStreaming: @Sendable (ModelOption, String?, @escaping @Sendable (String) -> Void) async throws -> StreamingTranscriptionHandle
    public var unloadModel: @Sendable () async -> Void = {}
    public var audioDurationSeconds: @Sendable (URL) -> Double = { _ in 0 }
}

extension TranscriptionClient: DependencyKey {
    public static var liveValue: Self {
        Self(
            prepareModelIfNeeded: { option in
                guard option.requiresDownload else { return }
                @Dependency(\.mlxClient) var mlxClient
                guard let pipelineModel = option.pipelineModel else { return }
                try await mlxClient.prepareModelIfNeeded(pipelineModel)
            },
            transcribe: { audioURL, option, mode, prompt, inputLanguageCode, outputLanguageCode in
                @Dependency(\.mlxClient) var mlxClient
                @Dependency(\.audioTrimClient) var trimClient
                @Dependency(\.audioSpeedClient) var speedClient
                @Dependency(\.logClient) var logClient
                if option.requiresDownload, let pipelineModel = option.pipelineModel {
                    try await mlxClient.prepareModelIfNeeded(pipelineModel)
                }

                @Shared(.trimSilenceEnabled) var trimEnabled
                @Shared(.autoSpeedEnabled) var speedEnabled

                let requestID = UUID().uuidString
                let requestStartUptime = ProcessInfo.processInfo.systemUptime
                var workingAudioURL = audioURL
                var generatedAudioURLs = Set<URL>()
                var stage = "setup"
                let inputDuration = audioFileDurationSeconds(audioURL)
                let inputSizeBytes = audioFileSizeBytes(audioURL) ?? 0

                logClient.dumpDebug(
                    "TranscriptionClient",
                    "Transcription request",
                    appDumpString(
                        [
                            "requestID": requestID,
                            "model": option.rawValue,
                            "mode": mode.rawValue,
                            "inputFile": audioURL.lastPathComponent,
                            "inputDuration": formatElapsedSeconds(inputDuration),
                            "inputSizeBytes": "\(inputSizeBytes)",
                            "trimEnabled": "\(trimEnabled)",
                            "autoSpeedEnabled": "\(speedEnabled)"
                        ]
                    )
                )

                if trimEnabled {
                    stage = "trim"
                    let trimStartUptime = ProcessInfo.processInfo.systemUptime
                    let beforeTrimDuration = audioFileDurationSeconds(workingAudioURL)
                    let trimmedURL = try await trimClient.trimSilence(workingAudioURL, Self.trimSilenceThreshold)
                    if trimmedURL != workingAudioURL {
                        generatedAudioURLs.insert(trimmedURL)
                        workingAudioURL = trimmedURL
                    }
                    let trimElapsed = ProcessInfo.processInfo.systemUptime - trimStartUptime
                    let afterTrimDuration = audioFileDurationSeconds(workingAudioURL)
                    logClient.dumpDebug(
                        "TranscriptionClient",
                        "Trim stage",
                        appDumpString(
                            [
                                "requestID": requestID,
                                "changedFile": "\(workingAudioURL != audioURL)",
                                "beforeDuration": formatElapsedSeconds(beforeTrimDuration),
                                "afterDuration": formatElapsedSeconds(afterTrimDuration),
                                "elapsed": formatElapsedSeconds(trimElapsed),
                                "workingFile": workingAudioURL.lastPathComponent
                            ]
                        )
                    )
                } else {
                    logClient.debug(
                        "TranscriptionClient",
                        "Trim stage skipped. requestID=\(requestID), trimEnabled=false"
                    )
                }

                let duration = await audioFileDurationSecondsAsync(workingAudioURL)
                if speedEnabled, let speedRate = Self.autoSpeedRate(for: duration) {
                    stage = "speed"
                    let speedStartUptime = ProcessInfo.processInfo.systemUptime
                    let beforeSpeedDuration = duration
                    let spedUpURL = try await speedClient.speedUp(workingAudioURL, speedRate)
                    if spedUpURL != workingAudioURL {
                        generatedAudioURLs.insert(spedUpURL)
                        workingAudioURL = spedUpURL
                    }
                    let speedElapsed = ProcessInfo.processInfo.systemUptime - speedStartUptime
                    let afterSpeedDuration = audioFileDurationSeconds(workingAudioURL)
                    logClient.dumpDebug(
                        "TranscriptionClient",
                        "Speed stage",
                        appDumpString(
                            [
                                "requestID": requestID,
                                "rate": speedRate.formatted(.number.precision(.fractionLength(2))),
                                "changedFile": "\(workingAudioURL != audioURL)",
                                "beforeDuration": formatElapsedSeconds(beforeSpeedDuration),
                                "afterDuration": formatElapsedSeconds(afterSpeedDuration),
                                "elapsed": formatElapsedSeconds(speedElapsed),
                                "workingFile": workingAudioURL.lastPathComponent
                            ]
                        )
                    )
                } else {
                    let resolvedRate = speedEnabled ? (Self.autoSpeedRate(for: duration) ?? 0) : 0
                    logClient.debug(
                        "TranscriptionClient",
                        "Speed stage skipped. requestID=\(requestID), autoSpeedEnabled=\(speedEnabled), rate=\(resolvedRate)"
                    )
                }

                defer {
                    for generatedURL in generatedAudioURLs {
                        try? FileManager.default.removeItem(at: generatedURL)
                    }
                }

                do {
                    stage = "backend"
                    let backendStartUptime = ProcessInfo.processInfo.systemUptime
                    let transcript: String

                    if option == .appleSpeech {
                        transcript = try await Self.transcribeWithAppleSpeech(workingAudioURL, preferredLanguageCode: inputLanguageCode)
                    } else {
                        transcript = try await mlxClient.transcribe(
                            workingAudioURL,
                            mode == .verbatim
                                ? .verbatim
                                : .smart(prompt: prompt ?? Self.defaultSmartPrompt),
                            inputLanguageCode,
                            outputLanguageCode
                        )
                    }

                    let backendElapsed = ProcessInfo.processInfo.systemUptime - backendStartUptime
                    let totalElapsed = ProcessInfo.processInfo.systemUptime - requestStartUptime
                    let workingDuration = audioFileDurationSeconds(workingAudioURL)
                    let outputCharacters = transcript.count

                    logClient.dumpDebug(
                        "TranscriptionClient",
                        "Transcription completed",
                        appDumpString(
                            [
                                "requestID": requestID,
                                "backend": option == .appleSpeech ? "apple-speech" : "mlx",
                                "workingFile": workingAudioURL.lastPathComponent,
                                "workingDuration": formatElapsedSeconds(workingDuration),
                                "backendElapsed": formatElapsedSeconds(backendElapsed),
                                "totalElapsed": formatElapsedSeconds(totalElapsed),
                                "outputCharacters": "\(outputCharacters)"
                            ]
                        )
                    )

                    return transcript
                } catch {
                    let failedElapsed = ProcessInfo.processInfo.systemUptime - requestStartUptime
                    logClient.error(
                        "TranscriptionClient",
                        "Transcription failed. requestID=\(requestID), stage=\(stage), elapsed=\(formatElapsedSeconds(failedElapsed)), model=\(option.rawValue), error=\(error.localizedDescription)"
                    )
                    throw error
                }
            },
            startStreaming: { option, inputLanguageCode, partialResultHandler in
                guard option == .appleSpeech else {
                    throw TranscriptionStreamingError.unsupported(option)
                }
                #if canImport(Speech)
                if #available(macOS 26, *) {
                    return try await AppleSpeechRuntime.startStreaming(
                        preferredLanguageCode: inputLanguageCode,
                        partialResultHandler: partialResultHandler
                    )
                }
                #endif
                throw AppleSpeechError.unavailable
            },
            unloadModel: {
                @Dependency(\.mlxClient) var mlxClient
                await mlxClient.unloadModel()
            },
            audioDurationSeconds: { url in
                audioFileDurationSeconds(url)
            }
        )
    }
}

extension TranscriptionClient: TestDependencyKey {
    public static var testValue: Self {
        Self(
            prepareModelIfNeeded: { _ in },
            transcribe: { _, _, _, _, _, _ in "Test transcription" },
            startStreaming: { _, _, _ in
                StreamingTranscriptionHandle(pushBuffer: { _ in }, finish: { "Test transcription" }, cancel: {})
            },
            unloadModel: {},
            audioDurationSeconds: { _ in 1.0 }
        )
    }
}

public extension DependencyValues {
    var transcriptionClient: TranscriptionClient {
        get { self[TranscriptionClient.self] }
        set { self[TranscriptionClient.self] = newValue }
    }
}

private func audioFileDurationSeconds(_ url: URL) -> Double {
    guard let file = try? AVAudioFile(forReading: url) else { return 0 }
    let sampleRate = file.fileFormat.sampleRate
    guard sampleRate > 0 else { return 0 }
    return Double(file.length) / sampleRate
}

private func audioFileDurationSecondsAsync(_ url: URL) async -> Double {
    await Task.detached(priority: .utility) {
        audioFileDurationSeconds(url)
    }.value
}

private extension TranscriptionClient {
    static let defaultSmartPrompt = "Clean up filler words and repeated phrases. Return a polished version of what was said."
    static let trimSilenceThreshold: Float = 0.003

    static func autoSpeedRate(for audioDuration: Double) -> Double? {
        switch audioDuration {
        case ..<45:
            return nil
        case 45..<90:
            return 1.1
        case 90..<180:
            return 1.2
        default:
            return 1.25
        }
    }
}

private func formatElapsedSeconds(_ seconds: Double) -> String {
    String(format: "%.3fs", seconds)
}

private func audioFileSizeBytes(_ url: URL) -> Int64? {
    let values = try? url.resourceValues(forKeys: [.fileSizeKey])
    guard let size = values?.fileSize else { return nil }
    return Int64(size)
}

private extension ModelOption {
    var pipelineModel: MLXPipelineModel? {
        switch self {
        case .appleSpeech:
            return nil
        case .qwen3ASR06B4bit:
            return .qwen3ASR06B4bit
        case .parakeetTDT06BV3:
            return .parakeetTDT06BV3
        case .whisperLargeV3Turbo:
            return .whisperLargeV3Turbo
        case .whisperTiny:
            return .whisperTiny
        case .mini3b:
            return .mini3b
        case .mini3b8bit:
            return .mini3b8bit
        }
    }
}

private extension TranscriptionClient {
    static func transcribeWithAppleSpeech(_ audioURL: URL, preferredLanguageCode: String?) async throws -> String {
        #if canImport(Speech)
        if #available(macOS 26, *) {
            return try await AppleSpeechRuntime.transcribe(audioURL: audioURL, preferredLanguageCode: preferredLanguageCode)
        }
        #endif
        throw AppleSpeechError.unavailable
    }
}

#if canImport(Speech)
@available(macOS 26, *)
private enum AppleSpeechRuntime {
    static func transcribe(audioURL: URL, preferredLanguageCode: String?) async throws -> String {
        guard SpeechTranscriber.isAvailable else {
            throw AppleSpeechError.unavailable
        }

        let supportedLocales = await SpeechTranscriber.supportedLocales
        let installedLocales = await SpeechTranscriber.installedLocales

        let supportedIDs = Set(supportedLocales.map(normalizedLocaleIdentifier))
        let installedSupportedLocales = installedLocales.filter { locale in
            supportedIDs.contains(normalizedLocaleIdentifier(locale))
        }

        guard !installedSupportedLocales.isEmpty else {
            throw AppleSpeechError.noInstalledLocale
        }

        let locale = preferredLocale(from: installedSupportedLocales, preferring: preferredLanguageCode)
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let audioFile = try AVAudioFile(forReading: audioURL)
        try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)

        var transcript = AttributedString()
        for try await result in transcriber.results {
            transcript += result.text
        }

        let text = String(transcript.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw AppleSpeechError.emptyTranscript
        }
        return text
    }

    /// Starts a live streaming session against `SpeechAnalyzer`'s native live-input path
    /// (as opposed to `transcribe`, above, which feeds it a completed file). Buffers pushed via
    /// the returned handle are converted to the analyzer's required format and yielded into an
    /// `AsyncStream<AnalyzerInput>` that the analyzer consumes continuously.
    ///
    /// NOTE: this streaming API (`start(inputSequence:)`, `AnalyzerInput`, `bestAvailableAudioFormat`,
    /// `result.isFinal`, `finalizeAndFinishThroughEndOfInput()`) was verified against public
    /// documentation/WWDC25 material for macOS 26, not against a real compiler — double-check
    /// against the actual SDK on first build.
    static func startStreaming(
        preferredLanguageCode: String?,
        partialResultHandler: @escaping @Sendable (String) -> Void
    ) async throws -> StreamingTranscriptionHandle {
        guard SpeechTranscriber.isAvailable else {
            throw AppleSpeechError.unavailable
        }

        let supportedLocales = await SpeechTranscriber.supportedLocales
        let installedLocales = await SpeechTranscriber.installedLocales
        let supportedIDs = Set(supportedLocales.map(normalizedLocaleIdentifier))
        let installedSupportedLocales = installedLocales.filter { locale in
            supportedIDs.contains(normalizedLocaleIdentifier(locale))
        }
        guard !installedSupportedLocales.isEmpty else {
            throw AppleSpeechError.noInstalledLocale
        }

        let locale = preferredLocale(from: installedSupportedLocales, preferring: preferredLanguageCode)
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw AppleSpeechError.unavailable
        }

        let (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()
        try await analyzer.start(inputSequence: inputSequence)

        let resultsTask = Task<String, Never> {
            var confirmedText = AttributedString()
            do {
                for try await result in transcriber.results {
                    if result.isFinal {
                        confirmedText += result.text
                        partialResultHandler(String(confirmedText.characters).trimmingCharacters(in: .whitespacesAndNewlines))
                    } else {
                        let preview = confirmedText + result.text
                        partialResultHandler(String(preview.characters).trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }
            } catch {
                // Results stream ended, typically because finalizeAndFinishThroughEndOfInput()
                // completed. The confirmed text accumulated so far is still returned below.
            }
            return String(confirmedText.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let converter = StreamingBufferConverter(targetFormat: analyzerFormat)

        let pushBuffer: @Sendable (AVAudioPCMBuffer) -> Void = { buffer in
            guard let converted = converter.convert(buffer) else { return }
            inputBuilder.yield(AnalyzerInput(buffer: converted))
        }

        let finish: @Sendable () async throws -> String = {
            inputBuilder.finish()
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            let text = await resultsTask.value
            guard !text.isEmpty else {
                throw AppleSpeechError.emptyTranscript
            }
            return text
        }

        let cancel: @Sendable () -> Void = {
            inputBuilder.finish()
            resultsTask.cancel()
        }

        return StreamingTranscriptionHandle(pushBuffer: pushBuffer, finish: finish, cancel: cancel)
    }

    private static func preferredLocale(from locales: [Locale], preferring code: String?) -> Locale {
        if let code, code != "auto" {
            let lowercased = code.lowercased()
            if let exactMatch = locales.first(where: { normalizedLocaleIdentifier($0) == lowercased }) {
                return exactMatch
            }
            if let languageMatch = locales.first(where: {
                $0.language.languageCode?.identifier.lowercased() == lowercased
            }) {
                return languageMatch
            }
        }

        let current = normalizedLocaleIdentifier(Locale.current)
        if let exactMatch = locales.first(where: { normalizedLocaleIdentifier($0) == current }) {
            return exactMatch
        }

        if let currentLanguage = Locale.current.language.languageCode?.identifier.lowercased(),
           let languageMatch = locales.first(where: {
               $0.language.languageCode?.identifier.lowercased() == currentLanguage
           })
        {
            return languageMatch
        }

        return locales[0]
    }

    private static func normalizedLocaleIdentifier(_ locale: Locale) -> String {
        locale.identifier
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
    }
}
/// Converts live microphone buffers (whatever format the input device provides) to the fixed
/// format `SpeechAnalyzer` requires, reusing a single `AVAudioConverter` across the session
/// (converters are relatively expensive to construct and assume a stable source format).
private final class StreamingBufferConverter: @unchecked Sendable {
    private let targetFormat: AVAudioFormat
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?

    init(targetFormat: AVAudioFormat) {
        self.targetFormat = targetFormat
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        lock.lock()
        defer { lock.unlock() }

        let inputFormat = buffer.format
        if converter == nil || sourceFormat != inputFormat {
            converter = AVAudioConverter(from: inputFormat, to: targetFormat)
            sourceFormat = inputFormat
        }
        guard let converter else { return nil }

        let ratio = targetFormat.sampleRate / max(inputFormat.sampleRate, 1)
        let outputCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity) else {
            return nil
        }

        var error: NSError?
        var suppliedInput = false
        let status = converter.convert(to: outputBuffer, error: &error) { _, inputStatus in
            if suppliedInput {
                inputStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            inputStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, error == nil else { return nil }
        return outputBuffer
    }
}

#endif

private enum AppleSpeechError: LocalizedError {
    case unavailable
    case noInstalledLocale
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Apple Speech is not available on this Mac."
        case .noInstalledLocale:
            return "No installed Apple Speech locale is available. Add a dictation language in System Settings."
        case .emptyTranscript:
            return "No speech detected."
        }
    }
}
