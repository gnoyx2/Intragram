import AppKit

// 정사각 캐릭터 원본(tool/icon_source.png) 하나로 플랫폼별 아이콘 마스터를 만듦.
// 사용: swift tool/make_icon_masters.swift tool/icon_source.png build/icon_master
// 배경색은 원본 왼쪽 위 모서리에서 읽고, 마지막 줄에 "background #RRGGBB"로 출력함
let args = CommandLine.arguments
guard args.count == 3, let source = NSImage(contentsOfFile: args[1]),
  let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
  FileHandle.standardError.write("usage: make_icon_masters.swift <source.png> <out-dir>\n".data(using: .utf8)!)
  exit(1)
}
let outDir = args[2]
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
let side = 1024
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func canvas() -> CGContext {
  let ctx = CGContext(
    data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
    space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  ctx.interpolationQuality = .high
  return ctx
}

func write(_ ctx: CGContext, _ name: String) {
  let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
  try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}

// 가운데에 size 크기로 원본을 그림. clip이 있으면 그 모양으로 자름
func draw(_ ctx: CGContext, size: Double, clip: ((CGRect) -> CGPath)? = nil, image: CGImage = cg) {
  let rect = CGRect(x: (Double(side) - size) / 2, y: (Double(side) - size) / 2, width: size, height: size)
  ctx.saveGState()
  if let clip { ctx.addPath(clip(rect)); ctx.clip() }
  ctx.draw(image, in: rect)
  ctx.restoreGState()
}

func rounded(_ ratio: Double) -> (CGRect) -> CGPath {
  { CGPath(roundedRect: $0, cornerWidth: $0.width * ratio, cornerHeight: $0.width * ratio, transform: nil) }
}
let circle: (CGRect) -> CGPath = { CGPath(ellipseIn: $0, transform: nil) }

// 원본 픽셀을 RGBA로 읽음 (위에서 아래 순서)
let w = cg.width, h = cg.height
var px = [UInt8](repeating: 0, count: w * h * 4)
let reader = CGContext(
  data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
  space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
reader.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
func rgb(_ i: Int) -> (Double, Double, Double) {
  (Double(px[i * 4]), Double(px[i * 4 + 1]), Double(px[i * 4 + 2]))
}
func dist(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
  ((a.0 - b.0) * (a.0 - b.0) + (a.1 - b.1) * (a.1 - b.1) + (a.2 - b.2) * (a.2 - b.2)).squareRoot()
}
var sum = (0.0, 0.0, 0.0)
for y in 0..<16 { for x in 0..<16 { let c = rgb(y * w + x); sum = (sum.0 + c.0, sum.1 + c.1, sum.2 + c.2) } }
let bg = (sum.0 / 256, sum.1 / 256, sum.2 / 256)

// 실루엣: 배경이 아닌 픽셀. 몸통에 둘러싸인 얼굴 표시(눈·부리)는 구멍으로 남김.
// 가장자리에서 시작해 몸통이 아닌 픽셀만 따라 칠하면 배경과 날개에만 닿고 얼굴 표시에는 닿지 않음
let bodyRef = rgb((h * 3 / 4) * w + w / 2)
func isBody(_ i: Int) -> Bool { dist(rgb(i), bodyRef) < 28 }
var reached = [Bool](repeating: false, count: w * h)
var stack: [Int] = []
for x in 0..<w { stack.append(x); stack.append((h - 1) * w + x) }
for y in 0..<h { stack.append(y * w); stack.append(y * w + w - 1) }
while let i = stack.popLast() {
  if reached[i] || isBody(i) { continue }
  reached[i] = true
  let x = i % w, y = i / w
  if x > 0 { stack.append(i - 1) }
  if x < w - 1 { stack.append(i + 1) }
  if y > 0 { stack.append(i - w) }
  if y < h - 1 { stack.append(i + w) }
}
var mask = [UInt8](repeating: 0, count: w * h * 4)
for i in 0..<(w * h) {
  let inside = isBody(i) || (reached[i] && dist(rgb(i), bg) > 40)
  if inside { mask[i * 4] = 255; mask[i * 4 + 1] = 255; mask[i * 4 + 2] = 255; mask[i * 4 + 3] = 255 }
}
let silhouette = CGContext(
  data: &mask, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
  space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!

// 캐릭터만 남긴 투명 배경판: 배경과의 색 거리로 알파를 정하고 가장자리에 섞인 배경색을 걷어냄
var cut = [UInt8](repeating: 0, count: w * h * 4)
for i in 0..<(w * h) {
  let p = rgb(i)
  let alpha = min(1, max(0, (dist(p, bg) - 25) / 35))
  if alpha == 0 { continue }
  let f = [p.0, p.1, p.2].enumerated().map { k, v -> Double in
    let b = [bg.0, bg.1, bg.2][k]
    return min(255, max(0, (v - (1 - alpha) * b) / alpha))
  }
  for k in 0..<3 { cut[i * 4 + k] = UInt8(f[k] * alpha) }
  cut[i * 4 + 3] = UInt8(alpha * 255)
}
let cutout = CGContext(
  data: &cut, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
  space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!

// iOS·Android 레거시: 풀블리드 (모서리는 OS가 깎음)
var ctx = canvas(); draw(ctx, size: 1024); write(ctx, "master_full")
// macOS·Linux: Big Sur 격자의 824px 둥근 판 + 투명 여백
ctx = canvas(); draw(ctx, size: 824, clip: rounded(0.225)); write(ctx, "master_macos")
// Windows: 캔버스를 거의 채우는 둥근 판
ctx = canvas(); draw(ctx, size: 896, clip: rounded(0.225)); write(ctx, "master_windows")
// 캐릭터만 남긴 판: iOS·macOS Icon Composer 레이어 (배경색은 icon.json이 모드별로 깜)
ctx = canvas(); draw(ctx, size: 1024, image: cutout); write(ctx, "cutout")
// Android 어댑티브 전경: 108dp 중 보이는 72dp에 캐릭터만 (배경색은 라이트·다크 배경 레이어가 깜)
ctx = canvas(); draw(ctx, size: 1024 * 72 / 108, image: cutout); write(ctx, "foreground")
// Android 테마 아이콘: 66dp 안전 원 안의 흰 실루엣
ctx = canvas(); draw(ctx, size: 1024 * 66 / 108, clip: circle, image: silhouette); write(ctx, "monochrome")
// 실행 화면 마크: Android 12 스플래시 안전 영역(지름 2/3) 안의 원형 원본
ctx = canvas(); draw(ctx, size: 1024 * 2 / 3, clip: circle); write(ctx, "launch_mark")
// Android 알림 small icon: 흰 실루엣이 폭의 92%
ctx = canvas(); draw(ctx, size: 1024 * 0.92, image: silhouette); write(ctx, "notification")

print(String(format: "background #%02X%02X%02X", Int(bg.0.rounded()), Int(bg.1.rounded()), Int(bg.2.rounded())))
