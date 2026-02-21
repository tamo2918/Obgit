import Foundation

struct VaultFileNode: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let url: URL
    let isDirectory: Bool
    let children: [VaultFileNode]

    nonisolated init(url: URL, isDirectory: Bool, children: [VaultFileNode] = []) {
        self.id = url.path
        self.name = url.lastPathComponent
        self.url = url
        self.isDirectory = isDirectory
        self.children = children
    }

    nonisolated var isMarkdown: Bool {
        guard !isDirectory else { return false }
        let ext = url.pathExtension.lowercased()
        return ext == "md" || ext == "markdown"
    }

    nonisolated var isImage: Bool {
        guard !isDirectory else { return false }
        let ext = url.pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "tiff", "bmp"].contains(ext)
    }

    nonisolated var isViewable: Bool { isMarkdown || isImage }

    nonisolated var outlineChildren: [VaultFileNode]? {
        isDirectory ? children : nil
    }
}

enum VaultFileTreeBuilder {
    nonisolated private static let ignoredNames: Set<String> = [".git"]

    nonisolated static func buildTree(at rootURL: URL) -> [VaultFileNode] {
        loadChildren(at: rootURL)
    }

    nonisolated static func firstMarkdownFile(in nodes: [VaultFileNode]) -> URL? {
        for node in nodes {
            if node.isDirectory {
                if let file = firstMarkdownFile(in: node.children) {
                    return file
                }
            } else if node.isMarkdown {
                return node.url
            }
        }
        return nil
    }

    nonisolated private static func loadChildren(at directoryURL: URL) -> [VaultFileNode] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents
            .filter { shouldInclude($0) }
            .compactMap { buildNode(at: $0) }
            .sorted(by: sortNodes)
    }

    nonisolated private static func shouldInclude(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if name.hasPrefix(".") { return false }
        return !ignoredNames.contains(name)
    }

    nonisolated private static func buildNode(at url: URL) -> VaultFileNode? {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        if values?.isSymbolicLink == true {
            return nil
        }

        let isDirectory = values?.isDirectory ?? false
        if isDirectory {
            return VaultFileNode(
                url: url,
                isDirectory: true,
                children: loadChildren(at: url)
            )
        } else {
            return VaultFileNode(url: url, isDirectory: false)
        }
    }

    nonisolated private static func sortNodes(_ lhs: VaultFileNode, _ rhs: VaultFileNode) -> Bool {
        if lhs.isDirectory != rhs.isDirectory {
            return lhs.isDirectory
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}
