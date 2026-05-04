import Foundation
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum FileImportError: LocalizedError {
    case directoryCreationFailed(String)
    case copyFailed(String)
    case fileNotReadable(String)

    var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let path): return "Could not create storage directory: \(path)"
        case .copyFailed(let detail): return "File copy failed: \(detail)"
        case .fileNotReadable(let path): return "Cannot read file: \(path)"
        }
    }
}

struct FileStorageService {
    // MARK: - Storage Directory

    /// Uses the app's Documents directory for reliable access without sandbox issues
    static var documentsRoot: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("SteelSync/BidDocuments", isDirectory: true)
    }

    static func ensureDirectory(_ url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                throw FileImportError.directoryCreationFailed(url.path)
            }
        }
    }

    static func bidFolder(for bidID: String) throws -> URL {
        let root = documentsRoot
        try ensureDirectory(root)
        let folder = root.appendingPathComponent(bidID, isDirectory: true)
        try ensureDirectory(folder)
        return folder
    }

    /// Per-expense folder for overhead receipts, kept under the shared
    /// Documents root but in a `overhead/` subdirectory so it never collides
    /// with bid folders (which sit at root level).
    static func overheadFolder(for expenseID: String) throws -> URL {
        let root = documentsRoot.appendingPathComponent("overhead", isDirectory: true)
        try ensureDirectory(root)
        let folder = root.appendingPathComponent(expenseID, isDirectory: true)
        try ensureDirectory(folder)
        return folder
    }

    /// Per-log folder for daily site log photos, kept under a `dailyLogs/`
    /// subdirectory of the shared Documents root.
    static func dailyLogFolder(for logID: String) throws -> URL {
        let root = documentsRoot.appendingPathComponent("dailyLogs", isDirectory: true)
        try ensureDirectory(root)
        let folder = root.appendingPathComponent(logID, isDirectory: true)
        try ensureDirectory(folder)
        return folder
    }

    // MARK: - File Operations

    /// Copies a file into the bid's local storage. Returns Result with Attachment or error.
    static func importFile(from sourceURL: URL, bidID: String) -> Result<Attachment, Error> {
        importFile(from: sourceURL, intoFolder: { try bidFolder(for: bidID) })
    }

    /// Copies a file into an overhead expense's local storage. Same contract
    /// as `importFile(from:bidID:)` but writes into the overhead subtree.
    static func importFile(from sourceURL: URL, overheadID: String) -> Result<Attachment, Error> {
        importFile(from: sourceURL, intoFolder: { try overheadFolder(for: overheadID) })
    }

    /// Copies a photo / doc into a daily-log's local storage.
    static func importFile(from sourceURL: URL, dailyLogID: String) -> Result<Attachment, Error> {
        importFile(from: sourceURL, intoFolder: { try dailyLogFolder(for: dailyLogID) })
    }

    /// Shared implementation — takes a folder-resolver closure so bid/overhead
    /// callers differ only in destination.
    private static func importFile(
        from sourceURL: URL,
        intoFolder folderProvider: () throws -> URL
    ) -> Result<Attachment, Error> {
        // Access security-scoped resource first (required for files picked via .fileImporter on iPad)
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }

        // Verify source exists and is readable
        guard FileManager.default.isReadableFile(atPath: sourceURL.path) else {
            return .failure(FileImportError.fileNotReadable(sourceURL.path))
        }

        do {
            let folder = try folderProvider()
            let filename = sourceURL.lastPathComponent
            var destURL = folder.appendingPathComponent(filename)

            // Handle duplicate filenames
            var counter = 1
            let nameWithoutExt = sourceURL.deletingPathExtension().lastPathComponent
            let ext = sourceURL.pathExtension
            while FileManager.default.fileExists(atPath: destURL.path) {
                destURL = folder.appendingPathComponent("\(nameWithoutExt)_\(counter).\(ext)")
                counter += 1
            }

            try FileManager.default.copyItem(at: sourceURL, to: destURL)

            let attrs = try FileManager.default.attributesOfItem(atPath: destURL.path)
            let fileSize = attrs[.size] as? Int64 ?? 0

            let attachment = Attachment(
                filename: destURL.lastPathComponent,
                fileSize: fileSize,
                fileURL: destURL
            )
            return .success(attachment)
        } catch let error as FileImportError {
            return .failure(error)
        } catch {
            return .failure(FileImportError.copyFailed(error.localizedDescription))
        }
    }

    /// Removes a file from local storage
    static func deleteFile(_ attachment: Attachment) {
        guard let url = attachment.fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Opens a file with the default system application.
    /// On macOS, copies to a temp location first to work around sandbox restrictions.
    static func openFile(_ attachment: Attachment) {
        guard let url = attachment.fileURL else { return }
        guard FileManager.default.isReadableFile(atPath: url.path) else { return }
        #if os(macOS)
        if let tempURL = copyToTempForSharing(url) {
            NSWorkspace.shared.open(tempURL)
        }
        #else
        UIApplication.shared.open(url)
        #endif
    }

    /// Shows file in Finder/Files.
    /// On macOS, copies to a temp location first to work around sandbox restrictions.
    @MainActor
    static func revealInFinder(_ attachment: Attachment) {
        guard let url = attachment.fileURL else { return }
        guard FileManager.default.isReadableFile(atPath: url.path) else { return }
        #if os(macOS)
        if let tempURL = copyToTempForSharing(url) {
            NSWorkspace.shared.activateFileViewerSelecting([tempURL])
        }
        #else
        PlatformService.shareItems([url])
        #endif
    }

    /// Copies a file from the app container to a temp directory so external apps can access it.
    #if os(macOS)
    private static func copyToTempForSharing(_ url: URL) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SteelSyncShared", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let destURL = tempDir.appendingPathComponent(url.lastPathComponent)
        // Remove stale copy if exists, then copy fresh
        try? FileManager.default.removeItem(at: destURL)
        do {
            try FileManager.default.copyItem(at: url, to: destURL)
            return destURL
        } catch {
            return nil
        }
    }
    #endif

    /// Presents an open panel for selecting plan documents
    #if os(macOS)
    @MainActor
    static func presentFilePicker() -> [URL] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            .pdf, .png, .jpeg, .tiff,
            UTType(filenameExtension: "dwg") ?? .data,
            UTType(filenameExtension: "dxf") ?? .data,
        ]
        panel.title = "Select Project Plans & Documents"
        let result = panel.runModal()
        return result == .OK ? panel.urls : []
    }
    #endif

    // MARK: - File Type Helpers

    static func iconName(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.richtext.fill"
        case "png", "jpg", "jpeg", "tiff", "tif": return "photo.fill"
        case "dwg", "dxf": return "ruler.fill"
        default: return "doc.fill"
        }
    }

    static func fileTypeLabel(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.uppercased()
        return ext.isEmpty ? "File" : ext
    }
}
