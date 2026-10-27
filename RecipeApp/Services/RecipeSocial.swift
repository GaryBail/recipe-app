import Foundation
import SwiftData
import UIKit

struct PhotoDTO: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let recipeId: String
    let authorId: String
    let authorName: String
    let width: Int
    let height: Int
    let url: String
    let thumbUrl: String
    let createdAt: String
}

struct RecipeSummaryDTO: Decodable, Sendable {
    let recipeId: String
    let likes: Int
    let likedByMe: Bool
    let photos: [PhotoDTO]
}

struct PopularDTO: Decodable, Identifiable, Sendable {
    let recipeId: String
    let likes: Int
    let recentLikes: Int
    let cover: PhotoDTO?

    var id: String { recipeId }
}

/// Лайки, популярное и фото рецептов на сервере.
struct RecipeSocialClient: Sendable {
    let api: APIClient

    static func fromSettings() -> RecipeSocialClient? {
        APIClient.fromSettings().map(RecipeSocialClient.init(api:))
    }

    func popular(limit: Int = 10) async throws -> [PopularDTO] {
        try await api.send("GET", "recipes/popular", query: [URLQueryItem(name: "limit", value: String(limit))])
    }

    func covers(for ids: [String]) async throws -> [String: PhotoDTO] {
        struct Body: Encodable { let ids: [String] }
        return try await api.send("POST", "recipes/covers", body: Body(ids: ids))
    }

    func summary(recipeId: String) async throws -> RecipeSummaryDTO {
        try await api.send("GET", "recipes/\(recipeId)")
    }

    func setLiked(_ liked: Bool, recipeId: String) async throws {
        let _: APIClient.Empty = try await api.send(liked ? "PUT" : "DELETE", "recipes/\(recipeId)/like")
    }

    func myLikes() async throws -> [String] {
        try await api.send("GET", "me/likes")
    }

    func upload(jpeg: Data, recipeId: String) async throws -> PhotoDTO {
        try await api.upload("recipes/\(recipeId)/photos", data: jpeg, contentType: "image/jpeg")
    }

    func deletePhoto(_ id: String) async throws {
        let _: APIClient.Empty = try await api.send("DELETE", "photos/\(id)")
    }

    func reportPhoto(_ id: String, reason: String) async throws {
        struct Body: Encodable { let reason: String }
        let _: APIClient.Empty = try await api.send("POST", "photos/\(id)/report", body: Body(reason: reason))
    }

    func url(_ path: String) -> URL? { api.mediaURL(path) }
}

/// Готовим фото к загрузке: уменьшаем до 2048 px по большей стороне и кодируем в JPEG.
/// (Сервер всё равно пережимает и убирает метаданные — это экономит трафик.)
enum PhotoPreparation {
    static func jpeg(from data: Data, maxSide: CGFloat = 2048) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.85)
    }
}

/// Избранное: работает и без аккаунта (хранится в телефоне), после входа — синхронизируется
/// с сервером, где лайки определяют «Популярное».
@MainActor
enum Favorites {
    static func toggle(_ recipe: Recipe, context: ModelContext) {
        recipe.isFavorite.toggle()
        recipe.favoritedAt = recipe.isFavorite ? .now : nil
        try? context.save()
        guard AuthSession.shared.isLoggedIn, let client = RecipeSocialClient.fromSettings() else { return }
        let liked = recipe.isFavorite
        let id = recipe.id
        Task { try? await client.setLiked(liked, recipeId: id) }
    }

    /// После входа: лайки с сервера → в избранное, локальное избранное → лайки на сервере.
    static func sync(context: ModelContext) async {
        guard AuthSession.shared.isLoggedIn, let client = RecipeSocialClient.fromSettings(),
              let remote = try? await client.myLikes() else { return }
        let remoteIds = Set(remote)
        let recipes = (try? context.fetch(FetchDescriptor<Recipe>())) ?? []
        for recipe in recipes {
            if remoteIds.contains(recipe.id) && !recipe.isFavorite {
                recipe.isFavorite = true
                recipe.favoritedAt = recipe.favoritedAt ?? .now
            } else if recipe.isFavorite && !remoteIds.contains(recipe.id) {
                try? await client.setLiked(true, recipeId: recipe.id)
            }
        }
        try? context.save()
    }
}
