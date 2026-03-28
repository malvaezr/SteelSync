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

    // MARK: - File Operations

    /// Copies a file into the bid's local storage. Returns Result with Attachment or error.
    static func importFile(from sourceURL: URL, bidID: String) -> Result<Attachment, Error> {
        // Verify source exists and is readable
        guard FileManager.default.isReadableFile(atPath: sourceURL.path) else {
            return .failure(FileImportError.fileNotReadable(sourceURL.path))
        }

        do {
            let folder = try bidFolder(for: bidID)
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

            // Access security-scoped resource if needed
            let accessed = sourceURL.startAccessingSecurityScopedResource()
            defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }

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

    /// Opens a file with the default system application
    static func openFile(_ attachment: Attachment) {
        guard let url = attachment.fileURL else { return }
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }

    /// Shows file in Finder/Files
    @MainActor
    static func revealInFinder(_ attachment: Attachment) {
        guard let url = attachment.fileURL else { return }
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        #else
        // On iOS, share the file instead
        PlatformService.shareItems([url])
        #endif
    }

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
