import CodexUsageCore
import Foundation

let semaphore = DispatchSemaphore(value: 0)
Task {
    defer { semaphore.signal() }
    do {
        let snapshot = try await CodexUsageService().fetch()
        print(MenuBarTitleFormatter().string(from: snapshot, mode: .expanded))
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(1)
    }
}
semaphore.wait()
