#!/usr/bin/env swift
import AppKit

// Vector source for the app icon; no external graphics packages are required.
let destination = CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.png"
let canvas = NSSize(width: 1024, height: 1024)
let image = NSImage(size: canvas)
image.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high
let tile = NSBezierPath(roundedRect: NSRect(x: 76, y: 76, width: 872, height: 872), xRadius: 196, yRadius: 196)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.23)
shadow.shadowBlurRadius = 30
shadow.shadowOffset = NSSize(width: 0, height: -14)
shadow.set()
NSColor(calibratedRed: 0.08, green: 0.37, blue: 0.81, alpha: 1).setFill()
tile.fill()
NSGraphicsContext.restoreGraphicsState()
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.22, green: 0.61, blue: 1.0, alpha: 1),
    NSColor(calibratedRed: 0.06, green: 0.35, blue: 0.85, alpha: 1)
])!
gradient.draw(in: tile, angle: -90)
NSGraphicsContext.saveGraphicsState()
tile.addClip()
let highlight = NSBezierPath(roundedRect: NSRect(x: 78, y: 78, width: 868, height: 868), xRadius: 194, yRadius: 194)
highlight.lineWidth = 3
NSColor.white.withAlphaComponent(0.19).setStroke()
highlight.stroke()
NSGraphicsContext.restoreGraphicsState()

// A shield protects a completed habit. The broad check stays legible at 16 px.
let shield = NSBezierPath()
shield.move(to: NSPoint(x: 512, y: 800))
shield.curve(to: NSPoint(x: 759, y: 708), controlPoint1: NSPoint(x: 601, y: 747), controlPoint2: NSPoint(x: 690, y: 722))
shield.line(to: NSPoint(x: 759, y: 510))
shield.curve(to: NSPoint(x: 512, y: 222), controlPoint1: NSPoint(x: 759, y: 372), controlPoint2: NSPoint(x: 654, y: 268))
shield.curve(to: NSPoint(x: 265, y: 510), controlPoint1: NSPoint(x: 370, y: 268), controlPoint2: NSPoint(x: 265, y: 372))
shield.line(to: NSPoint(x: 265, y: 708))
shield.curve(to: NSPoint(x: 512, y: 800), controlPoint1: NSPoint(x: 334, y: 722), controlPoint2: NSPoint(x: 423, y: 747))
shield.close()
NSGraphicsContext.saveGraphicsState()
let symbolShadow = NSShadow()
symbolShadow.shadowColor = NSColor(calibratedRed: 0.01, green: 0.16, blue: 0.45, alpha: 0.17)
symbolShadow.shadowBlurRadius = 14
symbolShadow.shadowOffset = NSSize(width: 0, height: -9)
symbolShadow.set()
NSColor.white.setFill()
shield.fill()
NSGraphicsContext.restoreGraphicsState()
let check = NSBezierPath()
check.move(to: NSPoint(x: 388, y: 520))
check.line(to: NSPoint(x: 478, y: 429))
check.line(to: NSPoint(x: 640, y: 610))
check.lineWidth = 66
check.lineCapStyle = .round
check.lineJoinStyle = .round
NSColor(calibratedRed: 0.10, green: 0.43, blue: 0.90, alpha: 1).setStroke()
check.stroke()
image.unlockFocus()

let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
    isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
image.draw(in: NSRect(origin: .zero, size: canvas), from: .zero, operation: .copy, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination))
