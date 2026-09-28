import AppKit
import Foundation

guard CommandLine.arguments.count == 3,
      let pid = Int32(CommandLine.arguments[1])
else {
    fputs("usage: quit_local_app.swift <pid> <executable-path>\n", stderr)
    exit(2)
}

guard let running = NSRunningApplication(processIdentifier: pid) else {
    exit(0)
}

let expectedExecutable = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL.path
guard running.bundleIdentifier == "com.willhsu.wmusic.local",
      running.executableURL?.standardizedFileURL.path == expectedExecutable
else {
    fputs("Refusing to quit a process outside this WMusic build.\n", stderr)
    exit(3)
}

guard running.terminate() else {
    fputs("WMusic did not accept the quit request.\n", stderr)
    exit(4)
}
