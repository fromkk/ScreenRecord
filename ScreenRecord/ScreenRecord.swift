//
//  ScreenRecord.swift
//  ScreenRecordSample
//
//  Created by Ueoka Kazuya on 2016/09/04.
//  Copyright © 2016年 fromKK. All rights reserved.
//

import Foundation
import AVFoundation

public protocol ScreenRecorderDelegate: class {
    func screenRecordDidStart(_ screenRecord: ScreenRecord) -> Void
    func screenRecordDidStop(_ screenRecord: ScreenRecord) -> Void
    func screenRecordDidCompletion(_ screenRecord: ScreenRecord, url: URL?) -> Void
    func screenRecord(screenRecord: ScreenRecord, didFailed error: ScreenRecord.ScreenRecordError) -> Void
}

extension ScreenRecorderDelegate {
    func screenRecordDidStart(_ screenRecord: ScreenRecord) {}
    func screenRecordDidStop(_ screenRecord: ScreenRecord) {}
    func screenRecordDidCompletion(_ screenRecord: ScreenRecord, url: URL?) {}
    func screenRecord(screenRecord: ScreenRecord, didFailed error: ScreenRecord.ScreenRecordError) {}
}

public protocol ScreenRecordable: class {
    associatedtype Completion
    func start(_ view: UIView?) -> Void
    func stop() -> Void
    var isRecording: Bool { get }
}

@objc open class ScreenRecord: NSObject {
    public enum Framerate {
        case f6
        case f10
        case f15
        case f30
        case f60
        
        func frameInterval() -> Int {
            switch self {
            case .f6:
                return 60 / 6
            case .f10:
                return 60 / 10
            case .f15:
                return 60 / 15
            case .f30:
                return 60 / 30
            case .f60:
                return 60 / 60
            }
        }
    }
    
    open static let shared: ScreenRecord = ScreenRecord()
    fileprivate override init() {
        self.queue = DispatchQueue(label: Constants.queue, attributes: [])
        super.init()
    }
    
    fileprivate enum Constants {
        static let identifier: String = "me.fromkk.ScreenRecord"
        static let queue: String = "me.fromkk.ScreenRecord.Queue"
        static let fileExtension: String = "m4v"
    }
    
    public enum ScreenRecordError: Error {
        case cacheDirectoryNotfound
        case failedCreateDirectory
        case emptyView
        case emptyURL
        case writerSetupFailed
        case writerAndInpuIsNotAvailable
        case writerInputCanNotAdd
        case emptyQueue
        case systemFailed
    }
    
    /// Public
    open var delegate: ScreenRecorderDelegate? = nil
    open var frameRate: Framerate = Framerate.f15
    fileprivate (set) open var isRecording: Bool = false
    
    /// Private
    fileprivate var view: UIView?
    fileprivate var queue: DispatchQueue
    fileprivate var currentURL: URL?
    fileprivate var writer: AVAssetWriter?
    fileprivate var writerInput: AVAssetWriterInput?
    fileprivate var writerInputPixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    fileprivate var firstFrameTime: CFAbsoluteTime?
    fileprivate var displayLink: CADisplayLink?
    fileprivate var startTimeStamp: CFTimeInterval = 0.0
    
    fileprivate func setup() -> ScreenRecordError? {
        guard let cacheDir: String = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first else {
            return ScreenRecordError.cacheDirectoryNotfound
        }
        let dir: String = "\(cacheDir)/\(Constants.identifier)"
        
        /// create directory if not exists.
        let fileManager: FileManager = FileManager()
        if !fileManager.fileExists(atPath: dir) {
            do {
                try fileManager.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: nil)
            } catch {
                return ScreenRecordError.failedCreateDirectory
            }
        }
        
        let path: String = "\(dir)/\(Date().timeIntervalSince1970).\(Constants.fileExtension)"
        self.currentURL = URL(fileURLWithPath: path)
        
        return nil
    }
    
    fileprivate func setupNotificationObserver() {
        NotificationCenter.default.addObserver(self, selector: #selector(ScreenRecord.applicationDidEnterBackground(_:)), name: NSNotification.Name.UIApplicationDidEnterBackground, object: nil)
    }
    
    fileprivate func unsetupNotificationObserver() {
        NotificationCenter.default.removeObserver(self)
    }
    
    func applicationDidEnterBackground(_ notification: Notification) {
        print(#function)
        self.stop()
    }
    
    fileprivate func failed(with error: ScreenRecordError) {
        DispatchQueue.main.async { [unowned self] in
            self.delegate?.screenRecord(screenRecord: self, didFailed: error)
        }
    }
    
    open func clearCaches() {
        guard let cacheDir: String = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first else {
            return
        }
        let dir: String = "\(cacheDir)/\(Constants.identifier)"
        
        /// create directory if not exists.
        let fileManager: FileManager = FileManager()
        if fileManager.fileExists(atPath: dir) {
            do {
                try fileManager.removeItem(atPath: dir)
            } catch {
                print("failed remove cache dir")
                return
            }
        }
    }
}

extension ScreenRecord: ScreenRecordable {
    public typealias Completion = (_ url: URL?) -> Void
    
    public func start(_ view: UIView? = UIApplication.shared.keyWindow) {
        if self.isRecording {
            return
        }
        
        self.view = view
        guard let view = self.view else {
            self.failed(with: ScreenRecordError.emptyView)
            return
        }
        
        if let error: ScreenRecordError = self.setup() {
            self.failed(with: error)
            return
        }
        
        guard let url: URL = self.currentURL else {
            self.failed(with: ScreenRecordError.emptyURL)
            return
        }
        
        /// writer
        do {
            self.writer = try AVAssetWriter(outputURL: url, fileType: AVFileTypeAppleM4V)
        } catch {
            self.failed(with: ScreenRecordError.writerSetupFailed)
            return
        }
        
        /// writerInput
        self.writerInput = AVAssetWriterInput(mediaType: AVMediaTypeVideo, outputSettings: [AVVideoCodecKey: AVVideoCodecH264, AVVideoWidthKey: view.frame.size.width, AVVideoHeightKey: view.frame.size.height])
        self.writerInput?.expectsMediaDataInRealTime = true
        
        guard let writer: AVAssetWriter = self.writer, let writerInput: AVAssetWriterInput = self.writerInput else {
            self.failed(with: ScreenRecordError.writerAndInpuIsNotAvailable)
            return
        }
        
        self.writerInputPixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerInput, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)])
        
        guard writer.canAdd(writerInput) else {
            self.failed(with: ScreenRecordError.writerInputCanNotAdd)
            return
        }
        
        writer.add(writerInput)
        writer.startWriting()
        writer.startSession(atSourceTime: kCMTimeZero)
        
        self.firstFrameTime = CFAbsoluteTimeGetCurrent()
        
        ///displayLink
        self.displayLink = CADisplayLink(target: self, selector: #selector(ScreenRecord.captureFrame(_:)))
        self.displayLink?.frameInterval = self.frameRate.frameInterval()
        self.displayLink?.add(to: RunLoop.current, forMode: RunLoopMode.commonModes)
        
        self.delegate?.screenRecordDidStart(self)
        
        self.setupNotificationObserver()
        self.isRecording = true
    }
    
    func captureFrame(_ displayLink: CADisplayLink) {
        self.queue.async {
            guard self.writerInput?.isReadyForMoreMediaData ?? false else {
                return
            }
            
            guard let pixelBufferPool = self.writerInputPixelBufferAdaptor?.pixelBufferPool else {
                print("pixelBufferPool is empty") //TODO: remove later
                self.failed(with: ScreenRecordError.systemFailed)
                self.stop()
                
                return
            }
            
            var pixelBufferOut: CVPixelBuffer? = nil
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &pixelBufferOut)
            
            guard let pixelBuffer = pixelBufferOut else {
                print("pixelBuffer is empty") //TODO: remove later
                self.failed(with: ScreenRecordError.systemFailed)
                self.stop()
                return
            }
            
            var createImageRef: CGImage?
            DispatchQueue.main.sync(execute: { [unowned self] in
                guard let view: UIView = self.view else {
                    self.failed(with: ScreenRecordError.emptyView)
                    self.stop()
                    return
                }
                UIGraphicsBeginImageContext(view.frame.size)
                view.layer.render(in: UIGraphicsGetCurrentContext()!)
                createImageRef = UIGraphicsGetCurrentContext()!.makeImage()
                UIGraphicsEndImageContext()
            })
            
            guard let imageRef: CGImage = createImageRef else {
                print("imageRef is empty") //TODO: remove later
                self.failed(with: ScreenRecordError.systemFailed)
                self.stop()
                return
            }
            
            CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))
            let context = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer), width: imageRef.width, height: imageRef.height, bitsPerComponent: imageRef.bitsPerComponent, bytesPerRow: imageRef.bytesPerRow, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: imageRef.bitmapInfo.rawValue)
            context?.draw(imageRef, in: CGRect(x: 0.0, y: 0.0, width: CGFloat(imageRef.width), height: CGFloat(imageRef.height)))
            CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))
            
            let timeScale: Double = 600
            let currentTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
            let elapsedTime: CFTimeInterval = currentTime - self.firstFrameTime!
            let presentTime: CMTime = CMTime(value: Int64(elapsedTime * timeScale), timescale: Int32(timeScale))
            
            if !(self.writerInputPixelBufferAdaptor!.append(pixelBuffer, withPresentationTime: presentTime)) {
                self.failed(with: ScreenRecordError.systemFailed)
                self.stop()
            }
        }
        
        if 0.0 == self.startTimeStamp {
            self.startTimeStamp = self.displayLink?.timestamp ?? 0.0
        }
    }
    
    public func stop() {
        if !self.isRecording {
            return
        }
        
        self.isRecording = false
        self.unsetupNotificationObserver()
        
        self.displayLink?.invalidate()
        self.startTimeStamp = 0.0
        
        DispatchQueue.main.async {
            self.delegate?.screenRecordDidStop(self)
        }
        self.queue.async {
            guard let writer: AVAssetWriter = self.writer else {
                return
            }
            
            if writer.status != AVAssetWriterStatus.completed && writer.status != AVAssetWriterStatus.unknown {
                self.writerInput?.markAsFinished()
            }
            
            writer.finishWriting(completionHandler: { [weak self] in
                DispatchQueue.main.async(execute: {
                    if let strongSelf = self {
                        strongSelf.delegate?.screenRecordDidCompletion(strongSelf, url: self?.currentURL)
                    }
                })
                })
        }
    }
}
