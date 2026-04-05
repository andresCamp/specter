//
//  DocumentFileSyncController.swift
//  Spectr
//
//  Created by Codex on 3/20/26.
//

import AppKit
import Combine
import Foundation
import SwiftUI

struct LiveExternalChange: Identifiable, Equatable {
    let id = UUID()
    let previousText: String
    let text: String
}

@MainActor
final class DocumentFileSyncController: ObservableObject {
    struct Conflict: Identifiable {
        let id = UUID()
    }

    @Published private(set) var conflict: Conflict?
    @Published private(set) var liveChange: LiveExternalChange?

    private weak var appKitDocument: NSDocument?
    private var textBinding: Binding<String>?
    private var monitoredFileURL: URL?
    private var fileMonitor: PresentedTextFileMonitor?

    func disconnect() {
        fileMonitor?.invalidate()
        fileMonitor = nil
        monitoredFileURL = nil
        appKitDocument = nil
        textBinding = nil
        conflict = nil
        liveChange = nil
    }

    func configure(
        window: NSWindow?,
        fileURL: URL?,
        text: Binding<String>
    ) {
        appKitDocument = window?.windowController?.document as? NSDocument
        textBinding = text

        let normalizedURL = fileURL?.standardizedFileURL
        guard monitoredFileURL != normalizedURL else { return }

        monitoredFileURL = normalizedURL
        conflict = nil
        liveChange = nil
        fileMonitor?.invalidate()
        fileMonitor = nil

        guard let normalizedURL else { return }

        let fileMonitor = PresentedTextFileMonitor(url: normalizedURL) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleFileMonitorEvent(event)
            }
        }

        self.fileMonitor = fileMonitor
        fileMonitor.start()
    }

    func reloadFromDisk() {
        conflict = nil
        liveChange = nil

        guard let document = appKitDocument else {
            applyFileContentsDirectly()
            return
        }

        guard let fileURL = document.fileURL, let fileType = document.fileType else {
            applyFileContentsDirectly()
            return
        }

        do {
            try document.revert(toContentsOf: fileURL, ofType: fileType)
        } catch {
            applyFileContentsDirectly()
        }
    }

    func keepLocalChanges() {
        conflict = nil
        liveChange = nil
    }

    func applyLiveExternalChange(_ diskText: String) {
        guard let textBinding else { return }

        let previousText = textBinding.wrappedValue
        guard diskText != previousText else {
            liveChange = nil
            conflict = nil
            return
        }

        conflict = nil
        let liveChange = LiveExternalChange(previousText: previousText, text: diskText)

        guard let appKitDocument else {
            self.liveChange = liveChange
            textBinding.wrappedValue = diskText
            return
        }

        let modificationDate = monitoredFileURL.flatMap(Self.modificationDate(at:))
        appKitDocument.performSynchronousFileAccess {
            self.liveChange = liveChange
            textBinding.wrappedValue = diskText

            // Mirror the bookkeeping that revert performs so AppKit no longer
            // thinks autosave is racing against a foreign disk version.
            if let modificationDate {
                appKitDocument.fileModificationDate = modificationDate
            }
            appKitDocument.updateChangeCount(.changeCleared)
        }
    }

    private func handleFileMonitorEvent(_ event: PresentedTextFileMonitor.Event) {
        switch event {
        case .changed(let fileURL):
            handlePresentedItemChange(at: fileURL)
        case .moved(let fileURL):
            monitoredFileURL = fileURL.standardizedFileURL
        }
    }

    private func handlePresentedItemChange(at fileURL: URL) {
        guard let textBinding else { return }

        guard let diskText = try? Self.readText(at: fileURL) else { return }
        guard diskText != textBinding.wrappedValue else {
            conflict = nil
            liveChange = nil
            return
        }

        if appKitDocument?.hasUnautosavedChanges == true {
            liveChange = nil
            conflict = Conflict()
            return
        }

        applyLiveExternalChange(diskText)
    }

    private func applyFileContentsDirectly() {
        guard let monitoredFileURL else { return }
        guard let diskText = try? Self.readText(at: monitoredFileURL) else { return }

        textBinding?.wrappedValue = diskText
    }

    private static func readText(at fileURL: URL) throws -> String {
        var readError: Error?
        var coordinatedData: Data?
        var coordinationError: NSError?

        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(readingItemAt: fileURL, options: [], error: &coordinationError) { coordinatedURL in
            do {
                coordinatedData = try Data(contentsOf: coordinatedURL)
            } catch {
                readError = error
            }
        }

        if let coordinationError {
            throw coordinationError
        }

        if let readError {
            throw readError
        }

        guard
            let coordinatedData,
            let text = String(data: coordinatedData, encoding: .utf8)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }

        return text
    }

    private static func modificationDate(at fileURL: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path(percentEncoded: false)))?[.modificationDate] as? Date
    }
}

private final class PresentedTextFileMonitor: NSObject, NSFilePresenter, @unchecked Sendable {
    enum Event {
        case changed(URL)
        case moved(URL)
    }

    private let lock = NSLock()
    private var _presentedItemURL: URL?

    var presentedItemURL: URL? {
        get { lock.withLock { _presentedItemURL } }
        set { lock.withLock { _presentedItemURL = newValue } }
    }

    let presentedItemOperationQueue: OperationQueue

    private let onEvent: @Sendable (Event) -> Void
    private var isRegistered = false

    init(
        url: URL,
        onEvent: @escaping @Sendable (Event) -> Void
    ) {
        _presentedItemURL = url
        self.onEvent = onEvent
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        presentedItemOperationQueue = queue
        super.init()
    }

    func start() {
        guard !isRegistered else { return }
        isRegistered = true
        NSFileCoordinator.addFilePresenter(self)
    }

    @MainActor
    func invalidate() {
        guard isRegistered else { return }
        isRegistered = false
        NSFileCoordinator.removeFilePresenter(self)
    }

    func presentedItemDidChange() {
        guard let url = presentedItemURL else { return }
        onEvent(.changed(url))
    }

    func presentedItemDidMove(to newURL: URL) {
        presentedItemURL = newURL
        onEvent(.moved(newURL))
    }
}
