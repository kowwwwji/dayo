// アプリアイコンの元画像（1024px の PNG）を描く。
//
//   swift scripts/make-icon.swift <出力.png> [--full-bleed]
//
// 既定は Mac 用（余白と影のある角丸）。`--full-bleed` は iOS 用で、角を OS が丸めるため正方形いっぱいに塗る。
// 図柄を変えたら scripts/make-appiconset.sh でアセットを作り直す。

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments.dropFirst()
guard let outputPath = arguments.first(where: { !$0.hasPrefix("--") }) else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.png> [--full-bleed]\n".utf8))
    exit(1)
}
let fullBleed = arguments.contains("--full-bleed")

let canvas: CGFloat = 1024
/// 図柄を描く座標系の一辺。Mac のアイコンの角丸部分の大きさに合わせている。
let unit: CGFloat = 824

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
guard let context = CGContext(
    data: nil, width: Int(canvas), height: Int(canvas), bitsPerComponent: 8, bytesPerRow: 0,
    space: colorSpace,
    // iOS のアイコンは透明を持てない
    bitmapInfo: (fullBleed ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue
) else {
    fatalError("could not create the bitmap context")
}

// 左上を原点にして、図柄の座標系（unit × unit）へ移す
context.translateBy(x: 0, y: canvas)
context.scaleBy(x: 1, y: -1)
if fullBleed {
    context.scaleBy(x: canvas / unit, y: canvas / unit)
} else {
    let margin = (canvas - unit) / 2
    context.translateBy(x: margin, y: margin)
}

// 地
let plate = CGRect(x: 0, y: 0, width: unit, height: unit)
let platePath = fullBleed
    ? CGPath(rect: plate, transform: nil)
    : CGPath(roundedRect: plate, cornerWidth: 185, cornerHeight: 185, transform: nil)

if !fullBleed {
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 24, color: color(0x000000, alpha: 0.3))
    context.addPath(platePath)
    context.setFillColor(color(0x3A6FE8))
    context.fillPath()
    context.restoreGState()
}

context.saveGState()
context.addPath(platePath)
context.clip()
let gradient = CGGradient(
    colorsSpace: colorSpace, colors: [color(0x5B9BFF), color(0x2F56D6)] as CFArray, locations: [0, 1]
)!
context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: unit), options: [])
context.restoreGState()

// カレンダーの紙
let sheet = CGRect(x: 142, y: 150, width: 540, height: 560)
let sheetPath = CGPath(roundedRect: sheet, cornerWidth: 64, cornerHeight: 64, transform: nil)

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: color(0x0B1E66, alpha: 0.35))
context.addPath(sheetPath)
context.setFillColor(color(0xFFFFFF))
context.fillPath()
context.restoreGState()

// 見出しの帯
let bandHeight: CGFloat = 125
context.saveGState()
context.addPath(sheetPath)
context.clip()
context.setFillColor(color(0xFF6659))
context.fill(CGRect(x: sheet.minX, y: sheet.minY, width: sheet.width, height: bandHeight))
context.restoreGState()

// 綴じ具
for x in [sheet.minX + 135, sheet.maxX - 135] {
    let ring = CGRect(x: x - 21, y: sheet.minY - 42, width: 42, height: 104)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -4), blur: 8, color: color(0x0B1E66, alpha: 0.3))
    context.addPath(CGPath(roundedRect: ring, cornerWidth: 21, cornerHeight: 21, transform: nil))
    context.setFillColor(color(0xFFFFFF))
    context.fillPath()
    context.restoreGState()
}

// 予定のブロック
func block(_ rect: CGRect, _ fill: CGColor) {
    context.addPath(CGPath(roundedRect: rect, cornerWidth: 24, cornerHeight: 24, transform: nil))
    context.setFillColor(fill)
    context.fillPath()
}
let left = sheet.minX + 60
block(CGRect(x: left, y: 322, width: 310, height: 84), color(0x4C86F5))
block(CGRect(x: left, y: 428, width: 210, height: 84), color(0xFFC04D))

// リマインダー（チェックの丸とタイトルの線）
let check = CGPoint(x: left + 38, y: 592)
context.setLineCap(.round)
context.setLineJoin(.round)
context.setStrokeColor(color(0x4C86F5))
context.setLineWidth(12)
context.strokeEllipse(in: CGRect(x: check.x - 32, y: check.y - 32, width: 64, height: 64))

context.move(to: CGPoint(x: check.x - 15, y: check.y + 1))
context.addLine(to: CGPoint(x: check.x - 4, y: check.y + 13))
context.addLine(to: CGPoint(x: check.x + 16, y: check.y - 12))
context.strokePath()

context.setStrokeColor(color(0xC7D0E4))
context.setLineWidth(20)
context.move(to: CGPoint(x: check.x + 66, y: check.y))
context.addLine(to: CGPoint(x: sheet.maxX - 80, y: check.y))
context.strokePath()

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
          URL(fileURLWithPath: outputPath) as CFURL, UTType.png.identifier as CFString, 1, nil
      )
else {
    fatalError("could not create the image")
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    fatalError("could not write \(outputPath)")
}
