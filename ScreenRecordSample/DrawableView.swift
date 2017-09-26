//
//  DrawableView.swift
//  Screen2GifSample
//
//  Created by Kazuya Ueoka on 2016/09/06.
//  Copyright © 2016年 fromKK. All rights reserved.
//

import UIKit

class DrawableView: UIView {
    class Path {
        var points: [CGPoint] = []
        func add(point: CGPoint) {
            self.points.append(point)
        }
    }

    var currentPath: Path?
    var paths: [Path] = []

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.isUserInteractionEnabled = true
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)

        self.isUserInteractionEnabled = true
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch: UITouch = touches.first else {
            return
        }

        let point: CGPoint = touch.location(in: self)
        self.currentPath = Path()
        self.currentPath?.add(point: point)
        self.setNeedsDisplay()
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch: UITouch = touches.first else {
            return
        }

        self.move(point: touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch: UITouch = touches.first else {
            return
        }

        self.move(point: touch.location(in: self))
        if let currentPath = self.currentPath {
            self.paths.append(currentPath)
        }

        self.currentPath = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>?, with event: UIEvent?) {
        guard let touch: UITouch = touches?.first else {
            return
        }

        self.move(point: touch.location(in: self))
        if let currentPath = self.currentPath {
            self.paths.append(currentPath)
        }

        self.currentPath = nil
    }

    private func move(point: CGPoint) {
        if let currentPath = self.currentPath {
            currentPath.add(point: point)
            self.setNeedsDisplay()
        }
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)

        guard let context: CGContext = UIGraphicsGetCurrentContext() else {
            return
        }

        if let currentPath = self.currentPath {
            UIGraphicsPushContext(context)
            context.setLineCap(CGLineCap.round)
            context.setLineWidth(5.0)
            context.setStrokeColor(UIColor.blue.cgColor)
            var didSet: Bool = false
            currentPath.points.forEach({ (point: CGPoint) in
                if !didSet {
                    context.move(to: point)
                    didSet = true
                } else {
                    context.addLine(to: point)
                }
            })
            context.strokePath()
            UIGraphicsPopContext()
        }

        self.paths.forEach { (path: Path) in
            UIGraphicsPushContext(context)
            context.setLineCap(CGLineCap.round)
            context.setLineWidth(5.0)
            context.setStrokeColor(UIColor.blue.cgColor)
            var didSet: Bool = false
            path.points.forEach({ (point: CGPoint) in
                if !didSet {
                    context.move(to: point)
                    didSet = true
                } else {
                    context.addLine(to: point)
                }
            })
            context.strokePath()
            UIGraphicsPopContext()
        }
    }
}
