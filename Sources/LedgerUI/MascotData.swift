// 由 design/mascot/build.py 生成，别手改。每张形象图里脸的位置（中心 x、中心 y、边长，按图宽算）。
import CoreGraphics

enum MascotData {
    static let faces: [String: (x: CGFloat, y: CGFloat, size: CGFloat)] = [
        "lilac-idle": (0.509, 0.428, 0.4),
        "orange-idle": (0.505, 0.428, 0.4),
        "star-idle": (0.484, 0.419, 0.4),
        "xiaxia-calm": (0.508, 0.399, 0.4),
        "xiaxia-cheer": (0.492, 0.381, 0.4),
        "xiaxia-idle": (0.493, 0.367, 0.4),
        "xiaxia-sharp": (0.506, 0.374, 0.4),
        "xiaxia-think": (0.508, 0.38, 0.4),
        "xiaxia-write": (0.516, 0.436, 0.4),
    ]
}
