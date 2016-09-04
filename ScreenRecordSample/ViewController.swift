//
//  ViewController.swift
//  ScreenRecordSample
//
//  Created by Ueoka Kazuya on 2016/09/04.
//  Copyright © 2016年 fromKK. All rights reserved.
//

import UIKit
import ScreenRecord
import MediaPlayer

func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
    return CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
}

class ViewController: UIViewController {
    
    enum Constants {
        static let recordButtonSize: CGSize = CGSize(width: 80.0, height: 80.0)
    }
    
    lazy var rectView: UIView = {
        let rectView: UIView = UIView()
        rectView.backgroundColor = UIColor.blueColor()
        rectView.addGestureRecognizer(self.panGestureRecognizer)
        return rectView
    }()
    @IBOutlet weak var recordButton: UIButton!
    lazy var panGestureRecognizer: UIPanGestureRecognizer = {
        let gesture: UIPanGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(ViewController.panGestureDidReceived(_:)))
        return gesture
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.insertSubview(self.rectView, atIndex: 0)
        
        self.recordButton.layer.cornerRadius = Constants.recordButtonSize.width / 2.0
        self.recordButton.layer.masksToBounds = true
        
        ScreenRecord.shared.delegate = self
        // Do any additional setup after loading the view, typically from a nib.
    }
    
    var didLayouted: Bool = false
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        if !self.didLayouted {
            self.rectView.frame = CGRect(origin: CGPoint(x: (self.view.frame.size.width - Constants.recordButtonSize.width) / 2.0, y: (self.view.frame.size.height - Constants.recordButtonSize.height) / 2.0), size: Constants.recordButtonSize)
            self.didLayouted = true
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    private var lastPoint: CGPoint = CGPoint.zero
    func panGestureDidReceived(sender: UIPanGestureRecognizer) {
        let currentPoint: CGPoint = sender.locationInView(self.view)
        switch sender.state {
        case UIGestureRecognizerState.Changed:
            fallthrough
        case UIGestureRecognizerState.Ended:
            fallthrough
        case UIGestureRecognizerState.Cancelled:
            let diff: CGPoint = currentPoint - lastPoint
            self.rectView.center = CGPoint(x: self.rectView.center.x + diff.x, y: self.rectView.center.y + diff.y)
        default:
            break
        }
        self.lastPoint = currentPoint
    }
    
    private var isRecording: Bool = false {
        didSet {
            if self.isRecording {
                self.recordButton.setTitle("Stop", forState: UIControlState.Normal)
            } else {
                self.recordButton.setTitle("Record", forState: UIControlState.Normal)
            }
        }
    }
    @IBAction func recordButtonTapped(sender: UIButton) {
        if !self.isRecording {
            ScreenRecord.shared.start()
        } else {
            ScreenRecord.shared.stop({ [unowned self] (url) in
                guard let url = url else {
                    return
                }
                
                let mediaPlayerViewController: MPMoviePlayerViewController = MPMoviePlayerViewController(contentURL: url)
                self.presentViewController(mediaPlayerViewController, animated: true, completion: nil)
            })
        }
    }
}

extension ViewController: ScreenRecorderDelegate {
    func screenRecordDidStart(screenRecord: ScreenRecord) {
        print(#function)
        
        self.isRecording = true
    }
    
    func screenRecordDidCompletion(screenRecord: ScreenRecord) {
        print(#function)
        
        self.isRecording = false
    }
    
    func screenRecord(screenRecord: ScreenRecord, didFailed error: ScreenRecord.Error) {
        print(#function)
        
        print(error)
        
        self.isRecording = false
    }
}
