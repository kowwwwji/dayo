// アプリアイコンの元画像（1024px の PNG）を描く。
//
//   swift scripts/make-icon.swift <出力.png> [--full-bleed] [--blank]
//
// 既定は Mac 用（余白と影のある角丸）。`--full-bleed` は iOS 用で、角を OS が丸めるため正方形いっぱいに塗る。
// `--blank` は紙と帯だけを描く（Mac の Dock で今日の日付を載せる台紙）。
// 図柄を変えたら scripts/make-appiconset.sh でアセットを作り直す。

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments.dropFirst()
guard let outputPath = arguments.first(where: { !$0.hasPrefix("--") }) else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.png> [--full-bleed] [--blank]\n".utf8))
    exit(1)
}
let fullBleed = arguments.contains("--full-bleed")
let blank = arguments.contains("--blank")

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

// 地（白い紙）
let plate = CGRect(x: 0, y: 0, width: unit, height: unit)
let platePath = fullBleed
    ? CGPath(rect: plate, transform: nil)
    : CGPath(roundedRect: plate, cornerWidth: 185, cornerHeight: 185, transform: nil)

if !fullBleed {
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 24, color: color(0x000000, alpha: 0.3))
    context.addPath(platePath)
    context.setFillColor(color(0xFFFFFF))
    context.fillPath()
    context.restoreGState()
}

context.saveGState()
context.addPath(platePath)
context.clip()
let gradient = CGGradient(
    colorsSpace: colorSpace, colors: [color(0xFFFFFF), color(0xF1F2F5)] as CFArray, locations: [0, 1]
)!
context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: unit), options: [])

// 見出しの帯。App/DockIcon.swift が下の余白に日付を描く（帯の高さを変えたら合わせる）
let bandHeight: CGFloat = 200
context.setFillColor(color(0xFF5A4D))
context.fill(CGRect(x: 0, y: 0, width: unit, height: bandHeight))
context.restoreGState()

// 綴じ具
for x in [unit * 0.25, unit * 0.75] {
    let ring = CGRect(x: x - 20, y: 52, width: 40, height: 96)
    context.addPath(CGPath(roundedRect: ring, cornerWidth: 20, cornerHeight: 20, transform: nil))
    context.setFillColor(color(0xFFFFFF))
    context.fillPath()
}

if !blank {
    // 予定のブロック
    func block(_ rect: CGRect, _ fill: CGColor) {
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 30, cornerHeight: 30, transform: nil))
        context.setFillColor(fill)
        context.fillPath()
    }
    let left: CGFloat = 122
    block(CGRect(x: left, y: 312, width: 410, height: 108), color(0x4C86F5))
    block(CGRect(x: left, y: 450, width: 280, height: 108), color(0xFFC04D))

    // リマインダー（チェックの丸とタイトルの線）
    let check = CGPoint(x: left + 46, y: 662)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setStrokeColor(color(0x4C86F5))
    context.setLineWidth(15)
    context.strokeEllipse(in: CGRect(x: check.x - 39, y: check.y - 39, width: 78, height: 78))

    context.move(to: CGPoint(x: check.x - 18, y: check.y + 1))
    context.addLine(to: CGPoint(x: check.x - 5, y: check.y + 16))
    context.addLine(to: CGPoint(x: check.x + 20, y: check.y - 14))
    context.strokePath()

    context.setStrokeColor(color(0xC7D0E4))
    context.setLineWidth(24)
    context.move(to: CGPoint(x: check.x + 84, y: check.y))
    context.addLine(to: CGPoint(x: unit - 150, y: check.y))
    context.strokePath()
}

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
