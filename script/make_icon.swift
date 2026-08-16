// 앱 아이콘 생성기.
// 디자인: 3중 과녁 링 위에 메뉴바 온도계를 올린다. 이름(Target)과 기능(온도)을
// 한 화면에서 읽히게 하려는 의도다. .icns 를 저장소에 커밋하지 않고
// 빌드할 때마다 여기서 만든다.
import AppKit
import CoreGraphics

let outputDirectory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

// 팔레트는 HotGoalCore/TemperaturePresentation.swift 의 3단계와 같은 값이다.
let backgroundTop = CGColor(srgbRed: 0.227, green: 0.247, blue: 0.278, alpha: 1) // #3A3F47
let backgroundBottom = CGColor(srgbRed: 0.110, green: 0.122, blue: 0.141, alpha: 1) // #1C1F24
let outline = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.92)
let mercury = CGColor(srgbRed: 1, green: 0.271, blue: 0.227, alpha: 1) // #FF453A
// 링 alpha 는 32px 축소본에서 정했다. 0.4 대에서는 링이 배경에 먹혀 사라졌다.
let ringCool = CGColor(srgbRed: 0.459, green: 0.878, blue: 0.420, alpha: 0.85) // #75E06B
let ringWarm = CGColor(srgbRed: 1, green: 0.831, blue: 0.322, alpha: 0.80) // #FFD452
let ringHot = CGColor(srgbRed: 1, green: 0.271, blue: 0.227, alpha: 0.75) // #FF453A

func drawIcon(size: CGFloat, into context: CGContext) {
    // macOS 26 아이콘 그리드: 1024 캔버스 기준 본체 824pt, 모서리 반경 185pt.
    let bodyInset = size * 100 / 1024
    let body = CGRect(x: bodyInset, y: bodyInset, width: size - bodyInset * 2, height: size - bodyInset * 2)
    let bodyPath = CGPath(
        roundedRect: body,
        cornerWidth: size * 185 / 1024,
        cornerHeight: size * 185 / 1024,
        transform: nil
    )

    // 본체는 위가 밝은 수직 그라디언트다. 링과 온도계가 아래쪽에서 더 잘 떨어져 보인다.
    context.saveGState()
    context.addPath(bodyPath)
    context.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [backgroundTop, backgroundBottom] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: body.midX, y: body.maxY),
        end: CGPoint(x: body.midX, y: body.minY),
        options: []
    )
    context.restoreGState()

    // 이하 도형은 128 단위 좌표계로 그린다. 미리보기 SVG 와 같은 좌표를 쓰려고
    // y 축을 뒤집어서 위에서 아래로 증가하게 맞춘다.
    context.saveGState()
    context.translateBy(x: body.minX, y: body.maxY)
    context.scaleBy(x: body.width / 128, y: -body.height / 128)

    // 과녁 링: 바깥부터 hot → warm → cool 순서다.
    // 32px 이하에서는 링 3개와 온도계가 서로 먹어서 뭉친 덩어리로 보였다. 그래서
    // 작은 크기에서는 바깥 링 하나만 두껍게 남긴다. (Apple 기본 아이콘도 작은
    // 크기에서 디테일을 줄인다.)
    let rings: [(radius: CGFloat, color: CGColor, width: CGFloat)] = size <= 32
        ? [(44, ringHot, 9)]
        : [(44, ringHot, 6), (30, ringWarm, 6), (16, ringCool, 6)]
    for ring in rings {
        context.setStrokeColor(ring.color)
        context.setLineWidth(ring.width)
        context.addEllipse(in: CGRect(
            x: 64 - ring.radius,
            y: 64 - ring.radius,
            width: ring.radius * 2,
            height: ring.radius * 2
        ))
        context.strokePath()
    }

    // 온도계 관 안쪽을 본체색으로 덮는다. 링이 관을 통과해 보이면 형태가 깨진다.
    let tube = CGPath(
        roundedRect: CGRect(x: 55.5, y: 27, width: 17, height: 46),
        cornerWidth: 8.5,
        cornerHeight: 8.5,
        transform: nil
    )
    context.addPath(tube)
    context.setFillColor(backgroundBottom)
    context.fillPath()

    context.setStrokeColor(mercury)
    context.setLineWidth(9)
    context.setLineCap(.round)
    context.move(to: CGPoint(x: 64, y: 40))
    context.addLine(to: CGPoint(x: 64, y: 66))
    context.strokePath()

    context.addPath(tube)
    context.setStrokeColor(outline)
    context.setLineWidth(4)
    context.strokePath()

    let bulb = CGRect(x: 51, y: 69, width: 26, height: 26)
    context.setFillColor(mercury)
    context.addEllipse(in: bulb)
    context.fillPath()
    context.setStrokeColor(outline)
    context.setLineWidth(4)
    context.addEllipse(in: bulb)
    context.strokePath()

    context.restoreGState()
}

func writePNG(pixels: Int, to url: URL) throws {
    guard let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "make_icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "failed to create \(pixels)px context"])
    }
    context.setAllowsAntialiasing(true)
    drawIcon(size: CGFloat(pixels), into: context)
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw NSError(domain: "make_icon", code: 2, userInfo: [NSLocalizedDescriptionKey: "failed to encode \(url.lastPathComponent)"])
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "make_icon", code: 3, userInfo: [NSLocalizedDescriptionKey: "failed to write \(url.lastPathComponent)"])
    }
}

// iconutil 이 요구하는 iconset 파일명 규칙.
let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

let directoryURL = URL(fileURLWithPath: outputDirectory, isDirectory: true)
try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
for variant in variants {
    try writePNG(pixels: variant.pixels, to: directoryURL.appendingPathComponent(variant.name))
}
