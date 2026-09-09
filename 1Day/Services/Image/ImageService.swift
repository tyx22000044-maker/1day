import UIKit

enum ImageService {
    static func compress(_ data: Data, maxBytes: Int = 1_000_000) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        var quality: CGFloat = 0.82
        var resized = image
        var compressed = resized.jpegData(compressionQuality: quality)

        while let data = compressed, data.count > maxBytes, quality > 0.18 {
            quality -= 0.12
            compressed = resized.jpegData(compressionQuality: quality)
        }

        if let data = compressed, data.count <= maxBytes {
            return data
        }

        let maxDimension: CGFloat = 1600
        let ratio = min(maxDimension / image.size.width, maxDimension / image.size.height, 1)
        guard ratio < 1 else { return compressed }

        let newSize = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.7)
    }
}
