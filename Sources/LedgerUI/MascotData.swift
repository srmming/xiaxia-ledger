// 由 design/mascot/build.py 生成，别手改。每张形象图里脸的位置（中心 x、中心 y、边长，按图宽算）。
import CoreGraphics

enum MascotData {
    static let faces: [String: (x: CGFloat, y: CGFloat, size: CGFloat)] = [
        "lilac-boy-idle": (0.509, 0.424, 0.4),
        "lilac-boy-think": (0.531, 0.423, 0.4),
        "lilac-idle": (0.509, 0.428, 0.4),
        "lilac-think": (0.531, 0.406, 0.4),
        "orange-boy-idle": (0.505, 0.438, 0.4),
        "orange-boy-think": (0.52, 0.419, 0.4),
        "orange-idle": (0.505, 0.428, 0.4),
        "orange-think": (0.475, 0.458, 0.4),
        "star-boy-idle": (0.507, 0.426, 0.4),
        "star-boy-think": (0.521, 0.409, 0.4),
        "star-idle": (0.484, 0.419, 0.4),
        "star-think": (0.516, 0.441, 0.4),
        "xiaxia-boy-calm": (0.509, 0.382, 0.4),
        "xiaxia-boy-celebrate": (0.523, 0.337, 0.4),
        "xiaxia-boy-cheer": (0.501, 0.376, 0.4),
        "xiaxia-boy-hello": (0.521, 0.385, 0.4),
        "xiaxia-boy-idle": (0.505, 0.376, 0.4),
        "xiaxia-boy-sharp": (0.504, 0.37, 0.4),
        "xiaxia-boy-sleep": (0.48, 0.455, 0.4),
        "xiaxia-boy-think": (0.514, 0.382, 0.4),
        "xiaxia-boy-worried": (0.516, 0.419, 0.4),
        "xiaxia-boy-write": (0.513, 0.421, 0.4),
        "xiaxia-calm": (0.508, 0.399, 0.4),
        "xiaxia-celebrate": (0.455, 0.37, 0.4),
        "xiaxia-cheer": (0.492, 0.381, 0.4),
        "xiaxia-hello": (0.48, 0.353, 0.4),
        "xiaxia-idle": (0.493, 0.367, 0.4),
        "xiaxia-sharp": (0.506, 0.374, 0.4),
        "xiaxia-sleep": (0.504, 0.408, 0.4),
        "xiaxia-think": (0.508, 0.38, 0.4),
        "xiaxia-worried": (0.502, 0.419, 0.4),
        "xiaxia-write": (0.516, 0.436, 0.4),
    ]
}
