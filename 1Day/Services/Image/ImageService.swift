import UIKit

enum ImageCompressionError: LocalizedError, Equatable {
    case unreadable
    /// 已经降到最小尺寸和最低质量仍然超限——明确报出来，而不是把超限的图当成功返回。
    case stillTooLarge(byteCount: Int, limit: Int)

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "图片无法读取，请重新选择或拍摄。"
        case .stillTooLarge(let byteCount, let limit):
            return "图片压缩后仍有 \(byteCount / 1024) KB，超过 \(limit / 1024) KB 上限。请减少张数，或换一张更简洁的截图。"
        }
    }
}

enum ImageService {
    /// 默认上限：单张 JPEG 1 MB，够服务商读清文字又不至于把请求体撑爆。
    static let defaultMaxBytes = 1_000_000

    /// 逐档降尺寸，最后一档还压不下就报超限。
    static let dimensionLadder: [CGFloat] = [1_600, 1_100, 800, 512]
    /// 每一档内逐档降质量；写成阶梯而不是减法，避免最低质量永远试不到。
    static let qualityLadder: [CGFloat] = [0.82, 0.70, 0.58, 0.46, 0.34, 0.22, 0.18]

    /// 压缩到 `maxBytes` 以内。返回值一定满足该上限，否则抛错。
    ///
    /// 旧实现先降质量、再缩放一次，缩放后只压一遍就不再检查，
    /// 高分辨率照片经常仍超限，却当成压缩成功发给服务商，用户看到的是泛化的网络错误。
    static func compressedData(_ data: Data, maxBytes: Int = ImageService.defaultMaxBytes) throws -> Data {
        guard let image = UIImage(data: data) else { throw ImageCompressionError.unreadable }

        var smallestAttempt = Int.max
        for side in dimensionLadder {
            for quality in qualityLadder {
                let candidate = try jpegData(for: image, longestSide: side, quality: quality)
                if candidate.count <= maxBytes { return candidate }
                smallestAttempt = min(smallestAttempt, candidate.count)
            }
        }
        throw ImageCompressionError.stillTooLarge(byteCount: smallestAttempt, limit: maxBytes)
    }

    /// 供既有调用点使用的非抛出版本：失败返回 nil，不再悄悄返回超限的原图。
    static func compress(_ data: Data, maxBytes: Int = defaultMaxBytes) -> Data? {
        try? compressedData(data, maxBytes: maxBytes)
    }

    private static func jpegData(for image: UIImage, longestSide: CGFloat, quality: CGFloat) throws -> Data {
        let resized = image.resizedForCompression(longestSide: longestSide)
        guard let data = resized.jpegData(compressionQuality: quality) else {
            throw ImageCompressionError.unreadable
        }
        return data
    }
}

private extension UIImage {
    func resizedForCompression(longestSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > longestSide, longest > 0 else { return self }

        let ratio = longestSide / longest
        let newSize = CGSize(width: max(1, (size.width * ratio).rounded()), height: max(1, (size.height * ratio).rounded()))
        // 必须固定 scale = 1：渲染器默认会跟随屏幕 scale（3x 设备上会画出三倍像素，
        // 等于「缩到 512」实际输出 1536 像素，字节数根本不降。
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
