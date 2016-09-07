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
    func screenRecordDidStart(screenRecord: ScreenRecord) -> Void
    func screenRecordDidStop(screenRecord: ScreenRecord) -> Void
    func screenRecordDidCompletion(screenRecord: ScreenRecord, url: NSURL?) -> Void
    func screenRecord(screenRecord: ScreenRecord, didFailed error: ScreenRecord.Error) -> Void
}

extension ScreenRecorderDelegate {
    func screenRecordDidStart(screenRecord: ScreenRecord) {}
    func screenRecordDidStop(screenRecord: ScreenRecord) {}
    func screenRecordDidCompletion(screenRecord: ScreenRecord, url: NSURL?) {}
    func screenRecord(screenRecord: ScreenRecord, didFailed error: ScreenRecord.Error) {}
}

public protocol ScreenRecordable: class {
    associatedtype Completion
    func start(let view: UIView?) -> Void
    func stop() -> Void
    var isRecording: Bool { get }
}

@objc public class ScreenRecord: NSObject {
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

    public static let shared: ScreenRecord = ScreenRecord()
    private override init() {
        self.queue = dispatch_queue_create(Constants.queue.cStringUsingEncoding(NSUTF8StringEncoding)!, nil)
        super.init()
    }

    private enum Constants {
        static let identifier: String = "me.fromkk.ScreenRecord"
        static let queue: String = "me.fromkk.ScreenRecord.Queue"
        static let fileExtension: String = "m4v"
    }

    public enum Error: ErrorType {
        case CacheDirectoryNotfound
        case FailedCreateDirectory
        case EmptyView
        case EmptyURL
        case WriterSetupFailed
        case WriterAndInpuIsNotAvailable
        case WriterInputCanNotAdd
        case EmptyQueue
        case SystemFailed
    }

    /// Public
    public var delegate: ScreenRecorderDelegate? = nil
    public var frameRate: Framerate = Framerate.f30
    private (set) public var isRecording: Bool = false

    /// Private
    private var view: UIView?
    private var queue: dispatch_queue_t
    private var currentURL: NSURL?
    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var writerInputPixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var firstFrameTime: CFAbsoluteTime?
    private var displayLink: CADisplayLink?
    private var startTimeStamp: CFTimeInterval = 0.0

    private func setup() -> Error? {
        guard let cacheDir: String = NSSearchPathForDirectoriesInDomains(.CachesDirectory, .UserDomainMask, true).first else {
            return Error.CacheDirectoryNotfound
        }
        let dir: String = "\(cacheDir)/\(Constants.identifier)"

        /// create directory if not exists.
        let fileManager: NSFileManager = NSFileManager()
        if !fileManager.fileExistsAtPath(dir) {
            do {
                try fileManager.createDirectoryAtPath(dir, withIntermediateDirectories: true, attributes: nil)
            } catch {
                return Error.FailedCreateDirectory
            }
        }

        let path: String = "\(dir)/\(NSDate().timeIntervalSince1970).\(Constants.fileExtension)"
        self.currentURL = NSURL(fileURLWithPath: path)

        return nil
    }

    private func snapshot() -> UIImage? {
        guard let view: UIView = self.view else {
            print("view is empty") //TODO: remove later
            return nil
        }

        UIGraphicsBeginImageContext(view.frame.size)
        view.layer.renderInContext(UIGraphicsGetCurrentContext()!)
        let image: UIImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }

    private func setupNotificationObserver() {
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(ScreenRecord.applicationDidEnterBackground(_:)), name: UIApplicationDidEnterBackgroundNotification, object: nil)
    }

    private func unsetupNotificationObserver() {
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }

    func applicationDidEnterBackground(notification: NSNotification) {
        print(#function)
        self.stop()
    }

    private func failed(with error: Error) {
        dispatch_async(dispatch_get_main_queue()) { [unowned self] in
            self.delegate?.screenRecord(self, didFailed: error)
        }
    }

    public func clearCaches() {
        guard let cacheDir: String = NSSearchPathForDirectoriesInDomains(.CachesDirectory, .UserDomainMask, true).first else {
            return
        }
        let dir: String = "\(cacheDir)/\(Constants.identifier)"

        /// create directory if not exists.
        let fileManager: NSFileManager = NSFileManager()
        if fileManager.fileExistsAtPath(dir) {
            do {
                try fileManager.removeItemAtPath(dir)
            } catch {
                print("failed remove cache dir")
                return
            }
        }
    }
}

extension ScreenRecord: ScreenRecordable {
    public typealias Completion = (url: NSURL?) -> Void

    public func start(let view: UIView? = UIApplication.sharedApplication().keyWindow) {
        if self.isRecording {
            return
        }

        self.view = view
        guard let view = self.view else {
            self.failed(with: Error.EmptyView)
            return
        }

        if let error: Error = self.setup() {
            self.failed(with: error)
            return
        }

        guard let url: NSURL = self.currentURL else {
            self.failed(with: Error.EmptyURL)
            return
        }

        /// writer
        do {
            self.writer = try AVAssetWriter(URL: url, fileType: AVFileTypeAppleM4V)
        } catch {
            self.failed(with: Error.WriterSetupFailed)
            return
        }

        /// writerInput
        self.writerInput = AVAssetWriterInput(mediaType: AVMediaTypeVideo, outputSettings: [AVVideoCodecKey: AVVideoCodecH264, AVVideoWidthKey: view.frame.size.width, AVVideoHeightKey: view.frame.size.height])
        self.writerInput?.expectsMediaDataInRealTime = true

        guard let writer: AVAssetWriter = self.writer, let writerInput: AVAssetWriterInput = self.writerInput else {
            self.failed(with: Error.WriterAndInpuIsNotAvailable)
            return
        }

        self.writerInputPixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerInput, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)])

        guard writer.canAddInput(writerInput) else {
            self.failed(with: Error.WriterInputCanNotAdd)
            return
        }

        writer.addInput(writerInput)
        writer.startWriting()
        writer.startSessionAtSourceTime(kCMTimeZero)

        self.firstFrameTime = CFAbsoluteTimeGetCurrent()

        ///displayLink
        self.displayLink = CADisplayLink(target: self, selector: #selector(ScreenRecord.captureFrame(_:)))
        self.displayLink?.frameInterval = self.frameRate.frameInterval()
        self.displayLink?.addToRunLoop(NSRunLoop.currentRunLoop(), forMode: NSRunLoopCommonModes)

        self.delegate?.screenRecordDidStart(self)

        self.setupNotificationObserver()
        self.isRecording = true
    }

    func captureFrame(displayLink: CADisplayLink) {
        dispatch_async(self.queue) {
            guard self.writerInput?.readyForMoreMediaData ?? false else {
                return
            }

            var snapshot: UIImage?
            dispatch_sync(dispatch_get_main_queue(), {
                snapshot = self.snapshot()
            })

            guard let image: UIImage = snapshot else {
                print("image is empty") //TODO: remove later
                self.failed(with: Error.SystemFailed)
                self.stop()
                return
            }

            guard let imageRef: CGImageRef = image.CGImage else {
                print("imageRef is empty") //TODO: remove later
                self.failed(with: Error.SystemFailed)
                self.stop()
                return
            }

            guard let pixelBufferPool = self.writerInputPixelBufferAdaptor?.pixelBufferPool else {
                print("pixelBufferPool is empty") //TODO: remove later
                self.failed(with: Error.SystemFailed)
                self.stop()

                return
            }

            var pixelBufferOut: CVPixelBuffer? = nil
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &pixelBufferOut)

            guard let pixelBuffer = pixelBufferOut else {
                print("pixelBuffer is empty") //TODO: remove later
                self.failed(with: Error.SystemFailed)
                self.stop()
                return
            }

            CVPixelBufferLockBaseAddress(pixelBuffer, 0)
            let context = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(pixelBuffer), CGImageGetWidth(imageRef), CGImageGetHeight(imageRef), CGImageGetBitsPerComponent(imageRef), CGImageGetBytesPerRow(imageRef), CGColorSpaceCreateDeviceRGB(), CGImageGetBitmapInfo(imageRef).rawValue)
            CGContextDrawImage(context, CGRect(x: 0.0, y: 0.0, width: CGFloat(CGImageGetWidth(imageRef)), height: CGFloat(CGImageGetHeight(imageRef))), imageRef)
            CVPixelBufferUnlockBaseAddress(pixelBuffer, 0)

            let timeScale: Double = 600
            let currentTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
            let elapsedTime: CFTimeInterval = currentTime - self.firstFrameTime!
            let presentTime: CMTime = CMTime(value: Int64(elapsedTime * timeScale), timescale: Int32(timeScale))

            if !(self.writerInputPixelBufferAdaptor!.appendPixelBuffer(pixelBuffer, withPresentationTime: presentTime)) {
                self.failed(with: Error.SystemFailed)
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

        dispatch_async(dispatch_get_main_queue()) {
            self.delegate?.screenRecordDidStop(self)
        }
        dispatch_async(self.queue) {
            guard let writer: AVAssetWriter = self.writer else {
                return
            }

            if writer.status != AVAssetWriterStatus.Completed && writer.status != AVAssetWriterStatus.Unknown {
                self.writerInput?.markAsFinished()
            }

            writer.finishWritingWithCompletionHandler({ [weak self] in
                dispatch_async(dispatch_get_main_queue(), {
                    if let strongSelf = self {
                        strongSelf.delegate?.screenRecordDidCompletion(strongSelf, url: self?.currentURL)
                    }
                })
            })
        }
    }
}
