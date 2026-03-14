#!/usr/bin/env swift
// make_icon.swift — Generates the WikipediaScraper app icon at all required sizes.
// Run from the project root:  swift make_icon.swift

import Foundation
import AppKit

// MARK: - Drawing

func renderIcon(ctx: CGContext, size s: CGFloat) {

    // Flip to top-left origin (Y increases downward), matching screen intuition
    ctx.translateBy(x: 0, y: s)
    ctx.scaleBy(x: 1, y: -1)

    let cs = CGColorSpaceCreateDeviceRGB()

    // ── 1. Background – radial gradient, deep forest ────────────────────────
    let bgGrad = CGGradient(colorsSpace: cs, colors: [
        NSColor(red: 0.12, green: 0.29, blue: 0.20, alpha: 1).cgColor,   // rich forest centre
        NSColor(red: 0.05, green: 0.13, blue: 0.09, alpha: 1).cgColor    // near-black edge
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(bgGrad,
        startCenter: CGPoint(x: s * 0.50, y: s * 0.50), startRadius: 0,
        endCenter:   CGPoint(x: s * 0.50, y: s * 0.50), endRadius: s * 0.75,
        options: CGGradientDrawingOptions(rawValue: 3))

    // ── 2. Decorative background tree silhouette (subtle) ───────────────────
    ctx.setFillColor(NSColor(red: 0.09, green: 0.22, blue: 0.15, alpha: 1).cgColor)

    func fillCircle(_ cx: CGFloat, _ cy: CGFloat, r: CGFloat) {
        ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    }

    // Canopy blobs (Y-flipped: small Y = top of image)
    let canopy: [(CGFloat, CGFloat, CGFloat)] = [
        (0.50, 0.14, 0.27), (0.50, 0.28, 0.22),
        (0.31, 0.26, 0.19), (0.69, 0.26, 0.19),
        (0.17, 0.36, 0.14), (0.83, 0.36, 0.14),
    ]
    for (cx, cy, r) in canopy { fillCircle(cx * s, cy * s, r: r * s) }
    // Trunk
    ctx.fill(CGRect(x: s * 0.46, y: s * 0.68, width: s * 0.08, height: s * 0.22))

    // ── 3. Glowing halo behind subject node ────────────────────────────────
    let haloGrad = CGGradient(colorsSpace: cs, colors: [
        NSColor(red: 0.85, green: 0.65, blue: 0.25, alpha: 0.45).cgColor,
        NSColor(red: 0.85, green: 0.65, blue: 0.25, alpha: 0.00).cgColor
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(haloGrad,
        startCenter: CGPoint(x: s * 0.50, y: s * 0.72), startRadius: s * 0.06,
        endCenter:   CGPoint(x: s * 0.50, y: s * 0.72), endRadius: s * 0.28,
        options: [])

    // ── 4. Connecting lines ─────────────────────────────────────────────────
    let lineCol = NSColor(red: 0.80, green: 0.60, blue: 0.25, alpha: 0.80).cgColor
    ctx.setStrokeColor(lineCol)
    ctx.setLineCap(.round)

    let sub  = CGPoint(x: s * 0.500, y: s * 0.720)   // subject (bottom)
    let parL = CGPoint(x: s * 0.295, y: s * 0.520)   // parent left
    let parR = CGPoint(x: s * 0.705, y: s * 0.520)   // parent right
    let gpLL = CGPoint(x: s * 0.150, y: s * 0.300)   // grandparent far-left
    let gpLR = CGPoint(x: s * 0.375, y: s * 0.300)   // grandparent inner-left
    let gpRL = CGPoint(x: s * 0.625, y: s * 0.300)   // grandparent inner-right
    let gpRR = CGPoint(x: s * 0.850, y: s * 0.300)   // grandparent far-right

    // Draw lines back-to-front (thick → thin)
    func line(_ a: CGPoint, _ b: CGPoint, width: CGFloat) {
        ctx.setLineWidth(width)
        ctx.move(to: a); ctx.addLine(to: b); ctx.strokePath()
    }

    // Trunk stub
    line(CGPoint(x: s * 0.50, y: s * 0.91), sub, width: s * 0.028)
    // Subject → parents
    line(sub, parL, width: s * 0.022)
    line(sub, parR, width: s * 0.022)
    // Parents → grandparents
    line(parL, gpLL, width: s * 0.018)
    line(parL, gpLR, width: s * 0.018)
    line(parR, gpRL, width: s * 0.018)
    line(parR, gpRR, width: s * 0.018)

    // ── 5. Node circles ─────────────────────────────────────────────────────

    // Grandparents – warm gold
    ctx.setFillColor(NSColor(red: 0.88, green: 0.68, blue: 0.30, alpha: 1).cgColor)
    for pt in [gpLL, gpLR, gpRL, gpRR] { fillCircle(pt.x, pt.y, r: s * 0.054) }

    // Parents – brighter gold
    ctx.setFillColor(NSColor(red: 0.95, green: 0.78, blue: 0.40, alpha: 1).cgColor)
    fillCircle(parL.x, parL.y, r: s * 0.064)
    fillCircle(parR.x, parR.y, r: s * 0.064)

    // Subject – brightest, cream-gold
    ctx.setFillColor(NSColor(red: 1.00, green: 0.93, blue: 0.70, alpha: 1).cgColor)
    fillCircle(sub.x, sub.y, r: s * 0.078)

    // ── 6. Person silhouette inside subject node ────────────────────────────
    let personCol = NSColor(red: 0.14, green: 0.28, blue: 0.20, alpha: 1).cgColor
    ctx.setFillColor(personCol)
    // Head
    fillCircle(sub.x, sub.y - s * 0.027, r: s * 0.022)
    // Shoulders/body
    let body = CGRect(x: sub.x - s * 0.023, y: sub.y - s * 0.006,
                      width: s * 0.046, height: s * 0.040)
    let bodyPath = CGMutablePath()
    bodyPath.addRoundedRect(in: body, cornerWidth: s * 0.012, cornerHeight: s * 0.012)
    ctx.addPath(bodyPath)
    ctx.fillPath()

    // ── 7. Rim on subject node ──────────────────────────────────────────────
    ctx.setStrokeColor(NSColor(red: 1.0, green: 0.98, blue: 0.90, alpha: 0.55).cgColor)
    ctx.setLineWidth(s * 0.009)
    ctx.strokeEllipse(in: CGRect(x: sub.x - s*0.078, y: sub.y - s*0.078,
                                  width: s * 0.156, height: s * 0.156))

    // ── 8. Small person silhouettes inside grandparent nodes ───────────────
    for (pt, scale) in [(gpLL, 0.75), (gpLR, 0.75), (gpRL, 0.75), (gpRR, 0.75)] {
        let k = CGFloat(scale)
        ctx.setFillColor(NSColor(red: 0.14, green: 0.24, blue: 0.18, alpha: 0.85).cgColor)
        fillCircle(pt.x, pt.y - s * 0.020 * k, r: s * 0.016 * k)
        let b2 = CGRect(x: pt.x - s*0.016*k, y: pt.y - s*0.003*k,
                        width: s*0.032*k, height: s*0.028*k)
        let bp2 = CGMutablePath()
        bp2.addRoundedRect(in: b2, cornerWidth: s*0.008*k, cornerHeight: s*0.008*k)
        ctx.addPath(bp2); ctx.fillPath()
    }

    // ── 9. Leaf accent (top-right) ──────────────────────────────────────────
    ctx.setFillColor(NSColor(red: 0.30, green: 0.60, blue: 0.40, alpha: 0.50).cgColor)
    // A small leaf shape using bezier
    let lx = s * 0.80, ly = s * 0.08, lr = s * 0.055
    let leafPath = CGMutablePath()
    leafPath.move(to: CGPoint(x: lx, y: ly - lr))
    leafPath.addQuadCurve(to: CGPoint(x: lx, y: ly + lr),
                          control: CGPoint(x: lx + lr * 1.4, y: ly))
    leafPath.addQuadCurve(to: CGPoint(x: lx, y: ly - lr),
                          control: CGPoint(x: lx - lr * 1.4, y: ly))
    ctx.addPath(leafPath); ctx.fillPath()

    // Vein
    ctx.setStrokeColor(NSColor(red: 0.20, green: 0.45, blue: 0.28, alpha: 0.50).cgColor)
    ctx.setLineWidth(s * 0.006)
    ctx.move(to: CGPoint(x: lx, y: ly - lr * 0.9))
    ctx.addLine(to: CGPoint(x: lx, y: ly + lr * 0.9))
    ctx.strokePath()

    // Mirror leaf (top-left, rotated)
    ctx.setFillColor(NSColor(red: 0.30, green: 0.60, blue: 0.40, alpha: 0.40).cgColor)
    let lx2 = s * 0.20, ly2 = s * 0.10
    let leafPath2 = CGMutablePath()
    leafPath2.move(to: CGPoint(x: lx2 - lr * 0.7, y: ly2))
    leafPath2.addQuadCurve(to: CGPoint(x: lx2 + lr * 0.7, y: ly2),
                           control: CGPoint(x: lx2, y: ly2 - lr * 1.3))
    leafPath2.addQuadCurve(to: CGPoint(x: lx2 - lr * 0.7, y: ly2),
                           control: CGPoint(x: lx2, y: ly2 + lr * 0.6))
    ctx.addPath(leafPath2); ctx.fillPath()
}

// MARK: - Size table and output

struct Slot {
    let file: String
    let px: Int
}

struct Catalog {
    let dir: String
    let slots: [Slot]
}

let catalogs: [Catalog] = [
    // macOS app icon
    Catalog(dir: "Sources/WikipediaScraperApp/Assets.xcassets/AppIcon.appiconset", slots: [
        Slot(file: "icon_16.png",   px: 16),
        Slot(file: "icon_32.png",   px: 32),
        Slot(file: "icon_64.png",   px: 64),
        Slot(file: "icon_128.png",  px: 128),
        Slot(file: "icon_256.png",  px: 256),
        Slot(file: "icon_512.png",  px: 512),
        Slot(file: "icon_1024.png", px: 1024),
    ]),
    // iPadOS app icon
    Catalog(dir: "Sources/WikipediaScraperIPad/Assets.xcassets/AppIcon.appiconset", slots: [
        Slot(file: "icon_ipad_20.png",   px: 20),
        Slot(file: "icon_ipad_29.png",   px: 29),
        Slot(file: "icon_ipad_40.png",   px: 40),
        Slot(file: "icon_ipad_58.png",   px: 58),
        Slot(file: "icon_ipad_76.png",   px: 76),
        Slot(file: "icon_ipad_80.png",   px: 80),
        Slot(file: "icon_ipad_152.png",  px: 152),
        Slot(file: "icon_ipad_167.png",  px: 167),
        Slot(file: "icon_ipad_1024.png", px: 1024),
    ]),
]

func writePNG(px: Int, to path: String) {
    let s = CGFloat(px)
    guard let ctx = CGContext(
        data: nil, width: px, height: px,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fputs("⚠ context failed \(px)\n", stderr); return }

    renderIcon(ctx: ctx, size: s)

    guard let cgImg = ctx.makeImage() else { fputs("⚠ image failed \(px)\n", stderr); return }
    let rep = NSBitmapImageRep(cgImage: cgImg)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        fputs("⚠ png encode failed \(px)\n", stderr); return
    }
    do {
        try png.write(to: URL(fileURLWithPath: path))
        print("✓ \(path)  (\(px)×\(px))")
    } catch {
        fputs("⚠ write failed \(path): \(error)\n", stderr)
    }
}

for catalog in catalogs {
    try? FileManager.default.createDirectory(atPath: catalog.dir, withIntermediateDirectories: true)
    for slot in catalog.slots {
        writePNG(px: slot.px, to: "\(catalog.dir)/\(slot.file)")
    }
}
print("Icon generation complete.")
