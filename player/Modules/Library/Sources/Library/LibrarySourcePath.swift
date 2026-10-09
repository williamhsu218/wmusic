import Foundation

/// Matches source paths after normalising symlinked parent directories, even
/// when the leaf was removed or its network volume is currently unmounted.
enum LibrarySourcePath {
    static func canonical(_ path: String) -> String {
        var ancestor = URL(fileURLWithPath: path).standardizedFileURL
        var missingComponents: [String] = []
        while !FileManager.default.fileExists(atPath: ancestor.path), ancestor.path != "/" {
            missingComponents.append(ancestor.lastPathComponent)
            ancestor.deleteLastPathComponent()
        }
        let resolvedAncestor: URL
        if let pointer = realpath(ancestor.path, nil) {
            resolvedAncestor = URL(fileURLWithPath: String(cString: pointer))
            free(pointer)
        } else {
            resolvedAncestor = ancestor
        }
        var resolved = resolvedAncestor
        for component in missingComponents.reversed() {
            resolved.appendPathComponent(component)
        }
        return resolved.path
    }

    static func contains(filePath: String, rootPath: String) -> Bool {
        let file = filePath.precomposedStringWithCanonicalMapping
        var root = rootPath.precomposedStringWithCanonicalMapping
        while root.hasSuffix("/"), root != "/" { root.removeLast() }
        return file == root || file.hasPrefix(root == "/" ? "/" : root + "/")
    }
}
