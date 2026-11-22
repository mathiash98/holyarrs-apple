import UIKit
#if !os(tvOS)
import AVFoundation
#endif

/// Starts the offline store at launch and hands background download events back to the system.
/// On tvOS (no durable storage for large files) it does nothing.
final class OfflineAppDelegate: NSObject, UIApplicationDelegate {
    private static var backgroundCompletion: (() -> Void)?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        #if !os(tvOS)
        OfflineStore.shared.activate()
        #endif
        return true
    }

    #if !os(tvOS)
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        Self.backgroundCompletion = completionHandler
        OfflineStore.shared.activate()
    }
    #endif

    static func finishBackgroundEvents() {
        backgroundCompletion?()
        backgroundCompletion = nil
    }
}

#if !os(tvOS)
/// Receives AVAssetDownloadURLSession events on the main queue and passes them to the store. Holds no state.
nonisolated final class OfflineSessionDelegate: NSObject, AVAssetDownloadDelegate {
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, willDownloadTo location: URL) {
        let id = assetDownloadTask.taskDescription
        let n = assetDownloadTask.taskIdentifier
        onMain { OfflineStore.shared.willDownload(id: id, task: n, to: location) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let id = task.taskDescription
        let n = task.taskIdentifier
        let failure = (error as NSError?).map {
            OfflineFailure(cancelled: $0.domain == NSURLErrorDomain && $0.code == NSURLErrorCancelled, message: $0.localizedDescription)
        }
        onMain { OfflineStore.shared.didComplete(id: id, task: n, failure: failure) }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        onMain { OfflineAppDelegate.finishBackgroundEvents() }
    }

    /// The session's delegate queue is the main queue, so this runs in place; the fallback keeps event order.
    private func onMain(_ body: @escaping @MainActor @Sendable () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { body() }
        } else {
            DispatchQueue.main.async { body() }
        }
    }
}
#endif
