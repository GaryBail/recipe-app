import UIKit

/// Фото к шагам своих рецептов. Необязательные, хранятся только на телефоне:
/// Application Support/StepPhotos/<id рецепта>/<номер шага>.jpg
enum StepPhotoStore {
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("StepPhotos", isDirectory: true)
    }

    static func url(recipeId: String, step: Int) -> URL {
        root.appendingPathComponent(safe(recipeId), isDirectory: true).appendingPathComponent("\(step).jpg")
    }

    static func image(recipeId: String, step: Int) -> UIImage? {
        UIImage(contentsOfFile: url(recipeId: recipeId, step: step).path)
    }

    static func hasPhotos(recipeId: String) -> Bool {
        let dir = root.appendingPathComponent(safe(recipeId), isDirectory: true)
        return !((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).isEmpty
    }

    /// Сохраняет уменьшенную копию (до 1600 px, JPEG).
    static func save(_ data: Data, recipeId: String, step: Int) throws {
        guard let jpeg = PhotoPreparation.jpeg(from: data, maxSide: 1600) else { return }
        let file = url(recipeId: recipeId, step: step)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try jpeg.write(to: file, options: .atomic)
    }

    static func deleteAll(recipeId: String) {
        try? FileManager.default.removeItem(at: root.appendingPathComponent(safe(recipeId), isDirectory: true))
    }

    private static func safe(_ id: String) -> String {
        id.filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }
}
