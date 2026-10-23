import SwiftUI

/// Procedural, darkened dirt tiling. Deterministic so it never flickers.
struct DirtBackground: View {
    var blockSize: CGFloat = 4   // size of one "texel"
    var texels = 16              // texels per tile edge
    var darkness = 0.55

    var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, size in
            let tile = blockSize * CGFloat(texels)
            let cols = Int(ceil(size.width / tile))
            let rows = Int(ceil(size.height / tile))
            for ty in 0..<rows {
                for tx in 0..<cols {
                    for y in 0..<texels {
                        for x in 0..<texels {
                            // Same texel pattern in every tile, like a real texture.
                            let idx = Self.hash(x, y) % Palette.dirt.count
                            let rect = CGRect(x: CGFloat(tx) * tile + CGFloat(x) * blockSize,
                                              y: CGFloat(ty) * tile + CGFloat(y) * blockSize,
                                              width: blockSize, height: blockSize)
                            ctx.fill(Path(rect), with: .color(Palette.dirt[idx]))
                        }
                    }
                }
            }
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(darkness)))
        }
        .drawingGroup()
        .ignoresSafeArea()
    }

    static func hash(_ x: Int, _ y: Int) -> Int {
        var h = UInt32(truncatingIfNeeded: x &* 374_761_393 &+ y &* 668_265_263)
        h = (h ^ (h >> 13)) &* 1_274_126_177
        return Int(h ^ (h >> 16))
    }
}
