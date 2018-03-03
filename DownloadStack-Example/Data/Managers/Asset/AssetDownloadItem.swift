//
//  AssetDownloadItem.swift
//  DownloadStack-Example
//
//  Created by William Boles on 15/01/2018.
//  Copyright © 2018 William Boles. All rights reserved.
//

import Foundation

enum DataRequestResult<T> {
    case success(T)
    case failure(Error)
}

typealias AssetDownloadItemCompletionHandler = ((_ result: DataRequestResult<Data>) -> Void)

enum Status: String {
    case waiting
    case downloading
    case suspended
    case canceled
}

class AssetDownloadItem {
    
    fileprivate let task: URLSessionDownloadTask
    
    var completionHandler: AssetDownloadItemCompletionHandler?
    
    var forceDownload = false
    var downloadPercentageComplete = 0.0
    var status = Status.waiting
    
    // MARK: - Init
    
    init(task: URLSessionDownloadTask) {
        self.task = task
    }
    
    // MARK: - Lifecycle
    
    func resume() {
        status = .downloading
        task.resume()
    }
    
    func pause() {
        status = .waiting
        forceDownload = false
        task.suspend()
    }
    
    func softCancel() {
        status = .suspended
        forceDownload = false
        task.suspend()
    }
    
    func hardCancel() {
        status = .canceled
        forceDownload = false
        task.cancel()
    }
    
    // MARK: - Meta
    
    var url: URL {
        return task.currentRequest!.url!
    }
    
    //MARK: - Coalesce
    
    func coalesce(_ additionalCompletionHandler: @escaping AssetDownloadItemCompletionHandler) {
        let initalCompletionHandler = completionHandler
        
        completionHandler = { (result) in
            if let initalCompletionClosure = initalCompletionHandler {
                initalCompletionClosure(result)
            }
            
            additionalCompletionHandler(result)
        }
    }
}

extension AssetDownloadItem: Equatable {
    static func ==(lhs: AssetDownloadItem, rhs: AssetDownloadItem) -> Bool {
        return lhs.url == rhs.url
    }
}
