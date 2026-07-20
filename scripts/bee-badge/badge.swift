#!/usr/bin/env swift
//
//  badge.swift
//  bee-badge
//
//  Composites the native 🐝 emoji onto the bottom-right corner of an app icon
//  PNG (or emits it alone on a transparent canvas, for layered icon formats
//  such as Xcode's Icon Composer `.icon` bundles).
//
//  See generate.sh for the invocations used to badge this fork's app icons,
//  and README.md in this directory for the rationale behind each flag.
//
//  Copyright © 2026 Mikey Ward. Licensed under the Apache License, Version 2.0.
//

import AppKit
import CoreGraphics
import Foundation

// MARK: - Diagnostics

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("bee-badge: error: \(message)\n".data(using: .utf8)!)
    exit(1)
}

// MARK: - CLI options

/// - `input`: source PNG to badge in place. Required unless `transparent` is set.
/// - `output`: destination PNG path.
/// - `canvas`: pixel size of the (square) canvas. Required (and only used) when `transparent` is set;
///   otherwise the canvas size is taken from `input`.
/// - `fraction`: badge size as a fraction of the icon's visible width/height (default 0.25 — ~1/4).
/// - `insetFraction`: clearance from the icon's edge, as a fraction of the icon's visible width/height.
/// - `anchor`: `"canvas"` anchors to the raw pixel canvas (use for icons the OS clips with its own
///   mask post-hoc, e.g. iOS's squircle — the file itself has no transparent margin to detect).
///   `"content"` auto-detects the tight bounding box of non-transparent pixels and anchors to that
///   (use for icons that already bake in their own shape + padding/shadow, e.g. macOS's icons).
/// - `transparent`: emit the badge alone on an empty canvas instead of compositing onto `input`.
/// - `flattenAlpha`: drop the alpha channel from the output (for icon variants that must ship fully
///   opaque, e.g. iOS's primary/light app icon). Incompatible with `anchor == "content"`, since an
///   opaque canvas has no transparency for content-bbox detection to key off.
struct Options {
    var input: String?
    var output: String
    var canvas: Int?
    var fraction: Double
    var insetFraction: Double
    var anchor: String
    var transparent: Bool
    var flattenAlpha: Bool
}

func parseOptions() -> Options {
    var iterator = CommandLine.arguments.dropFirst().makeIterator()
    var input: String?
    var output: String?
    var canvas: Int?
    var fraction = 0.25
    var insetFraction = 0.05
    var anchor = "content"
    var transparent = false
    var flattenAlpha = false

    while let arg = iterator.next() {
        switch arg {
        case "--input": input = iterator.next()
        case "--output": output = iterator.next()
        case "--canvas": canvas = iterator.next().flatMap(Int.init)
        case "--fraction": fraction = iterator.next().flatMap(Double.init) ?? fraction
        case "--inset-fraction": insetFraction = iterator.next().flatMap(Double.init) ?? insetFraction
        case "--anchor": anchor = iterator.next() ?? anchor
        case "--transparent": transparent = true
        case "--flatten-alpha": flattenAlpha = true
        default: fail("unrecognized argument '\(arg)'")
        }
    }

    guard let output else { fail("--output is required") }
    if transparent {
        guard canvas != nil else { fail("--canvas is required when --transparent is set") }
        anchor = "canvas"
    } else {
        guard input != nil else { fail("--input is required unless --transparent is set") }
    }
    guard anchor == "canvas" || anchor == "content" else {
        fail("--anchor must be 'canvas' or 'content', got '\(anchor)'")
    }
    guard !(anchor == "content" && flattenAlpha) else {
        fail("--anchor content requires transparency to detect against; incompatible with --flatten-alpha")
    }

    return Options(input: input, output: output, canvas: canvas, fraction: fraction,
                    insetFraction: insetFraction, anchor: anchor, transparent: transparent,
                    flattenAlpha: flattenAlpha)
}

// MARK: - Raw RGBA canvas

/// A directly-addressable RGBA8 bitmap backing a `CGContext`, so we can both draw with Core
/// Graphics/AppKit and inspect individual pixels afterwards (for bounding-box detection and the
/// post-composite sanity check below).
///
/// Pixel accessors use image-pixel space (origin top-left, row 0 = top), matching `CGImage`
/// cropping and `CGImageSource`/`CGImageDestination` conventions. Drawing through `context` uses
/// Quartz's native space (origin bottom-left, y-up) — `imagePixelRect(fromQuartzRect:)` below
/// converts between the two.
final class RGBACanvas {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let context: CGContext
    private let buffer: UnsafeMutablePointer<UInt8>

    /// - Parameter opaque: when true, the backing format has no real alpha channel (writes a
    ///   fully-opaque PNG). When false, alpha is preserved (premultiplied) end to end.
    init(width: Int, height: Int, opaque: Bool) {
        self.width = width
        self.height = height
        self.bytesPerRow = width * 4
        self.buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bytesPerRow * height)
        buffer.initialize(repeating: 0, count: bytesPerRow * height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let alphaInfo: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast
        guard let ctx = CGContext(data: buffer, width: width, height: height, bitsPerComponent: 8,
                                   bytesPerRow: bytesPerRow, space: colorSpace,
                                   bitmapInfo: alphaInfo.rawValue) else {
            fail("failed to create a \(width)x\(height) bitmap context")
        }
        self.context = ctx
    }

    deinit { buffer.deallocate() }

    /// Alpha byte at image-pixel coordinates. Only meaningful when the canvas was created with
    /// `opaque: false` — an opaque canvas's alpha byte is unused padding, not real data.
    func alpha(x: Int, y: Int) -> UInt8 { buffer[y * bytesPerRow + x * 4 + 3] }

    /// RGB bytes at image-pixel coordinates.
    func rgb(x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
        let o = y * bytesPerRow + x * 4
        return (buffer[o], buffer[o + 1], buffer[o + 2])
    }

    func makeCGImage() -> CGImage {
        guard let image = context.makeImage() else { fail("failed to render bitmap context to a CGImage") }
        return image
    }

    /// Tight bounding box (image-pixel space) of pixels whose alpha exceeds `threshold`. Requires
    /// an alpha-preserving canvas (`opaque: false`) — see `alpha(x:y:)`.
    func contentBoundingBox(alphaThreshold: UInt8 = 10) -> (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let rowStart = y * bytesPerRow
            for x in 0..<width where buffer[rowStart + x * 4 + 3] > alphaThreshold {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return (minX, minY, maxX, maxY)
    }
}

/// Converts a rect in Quartz drawing space (origin bottom-left, y-up) to image-pixel space
/// (origin top-left, y-down, integer-inclusive bounds), clamped to the canvas.
func imagePixelRect(fromQuartzRect r: CGRect, canvasWidth: Int, canvasHeight: Int) -> (x0: Int, y0: Int, x1: Int, y1: Int) {
    let yTop = CGFloat(canvasHeight) - r.maxY
    let yBottom = CGFloat(canvasHeight) - r.minY
    let x0 = max(0, Int(r.minX.rounded(.down)))
    let x1 = min(canvasWidth - 1, Int(r.maxX.rounded(.up)) - 1)
    let y0 = max(0, Int(yTop.rounded(.down)))
    let y1 = min(canvasHeight - 1, Int(yBottom.rounded(.up)) - 1)
    return (x0, y0, x1, y1)
}

// MARK: - PNG I/O

func loadCGImage(path: String) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fail("could not load PNG at '\(path)'")
    }
    return image
}

func writePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let destination = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil) else {
        fail("could not create a PNG destination for '\(path)'")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        fail("failed to write PNG to '\(path)'")
    }
}

// MARK: - Bee glyph

/// Renders "🐝" via the system's Apple Color Emoji font at high fidelity, then crops tightly to
/// its visible pixels. Composited elsewhere via aspect-fit, so the *visible glyph* — not its
/// font em-box, which has considerable built-in whitespace — is what ends up sized to `fraction`
/// of the icon.
func renderBeeGlyph() -> CGImage {
    let refCanvasSize = 1024
    let refPointSize: CGFloat = 760
    let canvas = RGBACanvas(width: refCanvasSize, height: refCanvasSize, opaque: false)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    let nsContext = NSGraphicsContext(cgContext: canvas.context, flipped: false)
    NSGraphicsContext.current = nsContext

    guard let emojiFont = NSFont(name: "Apple Color Emoji", size: refPointSize) else {
        fail("Apple Color Emoji font is unavailable on this system")
    }
    let attributed = NSAttributedString(string: "\u{1F41D}", attributes: [.font: emojiFont]) // 🐝
    let stringSize = attributed.size()
    let origin = CGPoint(x: (CGFloat(refCanvasSize) - stringSize.width) / 2,
                          y: (CGFloat(refCanvasSize) - stringSize.height) / 2)
    attributed.draw(at: origin)
    nsContext.flushGraphics()

    guard let bbox = canvas.contentBoundingBox() else {
        fail("rendered bee glyph produced no visible pixels")
    }
    let cropRect = CGRect(x: bbox.minX, y: bbox.minY,
                           width: bbox.maxX - bbox.minX + 1, height: bbox.maxY - bbox.minY + 1)
    guard let cropped = canvas.makeCGImage().cropping(to: cropRect) else {
        fail("failed to crop the bee glyph to its visible bounds")
    }
    return cropped
}

// MARK: - Main

let options = parseOptions()

// 1. Set up the destination canvas: either the loaded input icon, or empty/transparent.
let backgroundImage: CGImage? = options.transparent ? nil : loadCGImage(path: options.input!)
let canvasSize: Int
if let backgroundImage {
    guard backgroundImage.width == backgroundImage.height else {
        fail("expected a square icon, got \(backgroundImage.width)x\(backgroundImage.height) for '\(options.input!)'")
    }
    canvasSize = backgroundImage.width
} else {
    canvasSize = options.canvas!
}

let canvas = RGBACanvas(width: canvasSize, height: canvasSize, opaque: options.flattenAlpha)
if let backgroundImage {
    canvas.context.draw(backgroundImage, in: CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))
}

// 2. Determine the icon's visible bounds (in Quartz space) to badge relative to.
let iconBoundsQuartz: CGRect
switch options.anchor {
case "content":
    guard let bbox = canvas.contentBoundingBox() else {
        fail("--anchor content requested but '\(options.input!)' has no visible (non-transparent) pixels")
    }
    let imagePixelBounds = CGRect(x: bbox.minX, y: bbox.minY,
                                   width: bbox.maxX - bbox.minX + 1, height: bbox.maxY - bbox.minY + 1)
    iconBoundsQuartz = CGRect(x: imagePixelBounds.minX,
                               y: CGFloat(canvasSize) - imagePixelBounds.maxY,
                               width: imagePixelBounds.width, height: imagePixelBounds.height)
default:
    iconBoundsQuartz = CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize)
}

// 3. Compute the bottom-right badge target rect within those bounds.
let referenceSize = min(iconBoundsQuartz.width, iconBoundsQuartz.height)
let targetSize = referenceSize * CGFloat(options.fraction)
let inset = referenceSize * CGFloat(options.insetFraction)
let targetRect = CGRect(x: iconBoundsQuartz.maxX - inset - targetSize,
                         y: iconBoundsQuartz.minY + inset,
                         width: targetSize, height: targetSize)
guard targetRect.minX >= 0, targetRect.minY >= 0 else {
    fail("badge target rect \(targetRect) falls outside the \(canvasSize)x\(canvasSize) canvas — reduce --fraction or --inset-fraction")
}

// 4. Render the bee glyph, aspect-fit and centered within targetRect.
let glyph = renderBeeGlyph()
let glyphAspect = CGFloat(glyph.width) / CGFloat(glyph.height)
var drawSize = targetRect.size
if glyphAspect > 1 {
    drawSize.height = drawSize.width / glyphAspect
} else {
    drawSize.width = drawSize.height * glyphAspect
}
let drawRect = CGRect(x: targetRect.midX - drawSize.width / 2, y: targetRect.midY - drawSize.height / 2,
                       width: drawSize.width, height: drawSize.height)

// Snapshot the target region's RGB before drawing, so we can assert afterwards that pixels
// actually changed — a real sanity check, not a "the code ran without throwing" check.
let region = imagePixelRect(fromQuartzRect: drawRect, canvasWidth: canvasSize, canvasHeight: canvasSize)
var before: [(UInt8, UInt8, UInt8)] = []
if region.x1 >= region.x0, region.y1 >= region.y0 {
    for y in region.y0...region.y1 {
        for x in region.x0...region.x1 {
            before.append(canvas.rgb(x: x, y: y))
        }
    }
}

canvas.context.draw(glyph, in: drawRect)

// 5. Sanity check: confirm the badge actually landed with visibly different pixels.
var changed = 0
var index = 0
if region.x1 >= region.x0, region.y1 >= region.y0 {
    for y in region.y0...region.y1 {
        for x in region.x0...region.x1 {
            let after = canvas.rgb(x: x, y: y)
            let (br, bg, bb) = before[index]
            if abs(Int(after.0) - Int(br)) > 8 || abs(Int(after.1) - Int(bg)) > 8 || abs(Int(after.2) - Int(bb)) > 8 {
                changed += 1
            }
            index += 1
        }
    }
}
let sampleCount = before.count
guard sampleCount > 0, Double(changed) / Double(sampleCount) > 0.05 else {
    fail("post-composite sanity check failed: only \(changed)/\(sampleCount) pixels in the badge region changed — the bee likely did not render")
}

// 6. Write the result.
writePNG(canvas.makeCGImage(), to: options.output)
print("bee-badge: wrote \(options.output) (\(canvasSize)x\(canvasSize) canvas, badge ~\(Int(targetSize))px, \(changed)/\(sampleCount) region pixels changed)")
