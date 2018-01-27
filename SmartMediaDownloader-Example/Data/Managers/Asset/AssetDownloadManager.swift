//
//  AssetDownloadManager.swift
//  SmartMediaDownloader-Example
//
//  Created by William Boles on 16/01/2018.
//  Copyright © 2018 William Boles. All rights reserved.
//

import Foundation

class AssetDownloadManager: NSObject {
    
    lazy var urlSession: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: UUID().uuidString)
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        
        return session
    }()
    
    private var waiting = [AssetDownloadItem]()
    private var downloading = [AssetDownloadItem]()
    private var canceled = [AssetDownloadItem]()
    
    private static let maximumConcurrentDownloadsResetValue = 4
    
    private var maximumConcurrentDownloads = AssetDownloadManager.maximumConcurrentDownloadsResetValue
        
    // MARK: - Singleton
    
    static let shared = AssetDownloadManager()
    
    // MARK: - Init
    
    override init() {
        super.init()
        NotificationCenter.default.addObserver(forName: Notification.Name.UIApplicationDidReceiveMemoryWarning, object: nil, queue: OperationQueue.main) {_ in
            for downloadAssetItem in self.canceled {
                downloadAssetItem.hardCancel()
            }
            
            self.canceled.removeAll()
        }
    }
    
    // MARK: - Download
    
    private func download(url: URL, forceDownload: Bool, completionHandler: @escaping AssetDownloadItemCompletionHandler) {
        if forceDownload {
            pauseDownloads()
        }
        
        if let (_, assetDownloadItem) = searchForDownloadingAssetDownloadItem(withURL: url) {
            coalesceSameURLAssetDownloads(assetDownloadItem: assetDownloadItem, forceDownload: forceDownload, completionHandler: completionHandler)
        } else if let (_, assetDownloadItem) = searchForWaitingAssetDownloadItem(withURL: url) {
            coalesceSameURLAssetDownloads(assetDownloadItem: assetDownloadItem, forceDownload: forceDownload, completionHandler: completionHandler)
        } else if let (index, assetDownloadItem) = searchForCanceledAssetDownloadItem(withURL: url) {
            assetDownloadItem.completionHandler = completionHandler
            assetDownloadItem.forceDownload = forceDownload
            
            waiting.append(assetDownloadItem)
            canceled.remove(at: index)
        } else {
            let downloadTask = urlSession.downloadTask(with: url)
            let assetDownloadItem = AssetDownloadItem(task: downloadTask)
            assetDownloadItem.completionHandler = completionHandler
            assetDownloadItem.forceDownload = forceDownload
            
            waiting.append(assetDownloadItem)
        }
    
        resumeDownloads()
    }
    
    private func coalesceSameURLAssetDownloads(assetDownloadItem: AssetDownloadItem, forceDownload: Bool, completionHandler: @escaping AssetDownloadItemCompletionHandler) {
        assetDownloadItem.coalesce(completionHandler)
        if forceDownload {
            assetDownloadItem.forceDownload = forceDownload
        }
    }
    
    func scheduleDownload(url: URL, forceDownload: Bool, completionHandler: @escaping AssetDownloadItemCompletionHandler) {
        download(url: url, forceDownload: forceDownload, completionHandler: completionHandler)
    }
    
    private func pauseDownloads() {
        for assetDownloadItem in downloading.reversed() {
            assetDownloadItem.pause()
            waiting.append(assetDownloadItem)
        }
        
        downloading.removeAll()
    }
    
    private func resumeDownloads() {
        updatedConcurrentDownloadLimitIfNeeded()
        
        for _ in downloading.count..<maximumConcurrentDownloads {
            guard let assetDownloadItem = waiting.last else {
                return
            }
            
            waiting.removeLast()
            downloading.append(assetDownloadItem)
            assetDownloadItem.resume()
        }
        
        generateReport()
    }
    
    private func updatedConcurrentDownloadLimitIfNeeded() {
        guard downloading.first?.forceDownload == false else {
            maximumConcurrentDownloads = 1
            return
        }
        
        guard let assetDownloadItem = waiting.last else {
            maximumConcurrentDownloads = AssetDownloadManager.maximumConcurrentDownloadsResetValue
            return
        }
        
        if assetDownloadItem.forceDownload {
            maximumConcurrentDownloads = 1
        } else {
            maximumConcurrentDownloads = AssetDownloadManager.maximumConcurrentDownloadsResetValue
        }
    }
    
    func cancelDownload(url: URL) {
        var assetDownloadItemToBeCanceled: AssetDownloadItem?
        
        for (index, assetDownloadItem) in downloading.enumerated() {
            if assetDownloadItem.url == url {
                assetDownloadItemToBeCanceled = assetDownloadItem
                downloading.remove(at: index)
                break
            }
        }
        
        if assetDownloadItemToBeCanceled == nil {
            for (index, assetDownloadItem) in waiting.enumerated() {
                if assetDownloadItem.url == url {
                    assetDownloadItemToBeCanceled = assetDownloadItem
                    waiting.remove(at: index)
                    break
                }
            }
        }
        
        if let assetDownloadItem = assetDownloadItemToBeCanceled {
            assetDownloadItem.softCancel()
            canceled.append(assetDownloadItem)
        }
        
        generateReport()
        
        resumeDownloads()
    }
    
    // MARK: - Search
    
    private func searchForAssetDownloadItem(withURL url: URL, in array: [AssetDownloadItem]) -> (Int, AssetDownloadItem)? {
        for (index, assetDownloadItem) in array.enumerated() {
            if assetDownloadItem.url == url {
                return (index, assetDownloadItem)
            }
        }
        
        return nil
    }
    
    fileprivate func searchForWaitingAssetDownloadItem(withURL url: URL) -> (Int, AssetDownloadItem)? {
        return searchForAssetDownloadItem(withURL: url, in: waiting)
    }
    
    fileprivate func searchForDownloadingAssetDownloadItem(withURL url: URL) -> (Int, AssetDownloadItem)? {
        return searchForAssetDownloadItem(withURL: url, in: downloading)
    }
    
    fileprivate func searchForCanceledAssetDownloadItem(withURL url: URL) -> (Int, AssetDownloadItem)? {
        return searchForAssetDownloadItem(withURL: url, in: canceled)
    }
    
    fileprivate func searchForAssetDownloadItem(withURLSessionTask sessionTask: URLSessionTask) -> (Int, AssetDownloadItem)? {
        guard let url = sessionTask.currentRequest?.url else {
            return nil
        }
        
        return searchForAssetDownloadItem(withURL: url, in: downloading)
    }
}

extension AssetDownloadManager: URLSessionDownloadDelegate {
    
    // MARK: - URLSessionDownloadDelegate
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        maximumConcurrentDownloads = AssetDownloadManager.maximumConcurrentDownloadsResetValue
        
        guard let (index, assetDownloadItem) = searchForAssetDownloadItem(withURLSessionTask: downloadTask) else {
            return
        }
        
        self.downloading.remove(at: index)
        self.resumeDownloads()
        
        do {
            let data = try Data(contentsOf: location)
            
            assetDownloadItem.completionHandler?(.success(data))
        } catch {
            assetDownloadItem.completionHandler?(.failure(APIError.invalidData))
        }
        
        generateReport()
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let (_, assetDownloadItem) = searchForAssetDownloadItem(withURLSessionTask: downloadTask)  else {
            return
        }
        
        let percentageComplete = Double(totalBytesWritten)/Double(totalBytesExpectedToWrite)
        assetDownloadItem.downloadPercentageComplete = percentageComplete
            
        generateReport()
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let (index, assetDownloadItem) = searchForAssetDownloadItem(withURLSessionTask: task)  else {
            return
        }
        
        self.downloading.remove(at: index)
        self.resumeDownloads()
        
        guard let error = error else {
            assetDownloadItem.completionHandler?(.failure(APIError.unknown))
            return
        }
        
        assetDownloadItem.completionHandler?(.failure(error))
        
        generateReport()
    }
}

extension AssetDownloadManager {
    
    // MARK: - Report
    
    private func generateReport() {
        print("-------------------------------")
        print("-       Download Report       -")
        print("-------------------------------")
        print("Date: \(Date())")
        print("Number of possible concurrent downloads: \(maximumConcurrentDownloads)")
        print("Number of items downloading: \(downloading.count)")
        print("Number of items waitng for download: \(waiting.count)")
        print("Number of items canceled for download: \(canceled.count)")
        
        print("")
        print("Items:")
        
        let combined = downloading + waiting + canceled
        
        if combined.count > 0 {
            for assetDownloadItem in combined {
                let percentage = (assetDownloadItem.downloadPercentageComplete*10000).rounded()/100
                print("\(assetDownloadItem.url.absoluteString) (\(percentage)%) \(assetDownloadItem.status.rawValue) \(assetDownloadItem.forceDownload ? "forced" : "unforced")")
            }
        } else {
            print("Empty")
        }
        
        print("")
    }
}