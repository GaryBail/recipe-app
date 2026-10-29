"""Тестовые данные для проверки приложения с настоящим сервером (CI, эмулятор Android).

Создаёт в базе сервера двух подтверждённых пользователей, сборки в сообществе, свой рецепт
и оценку со уведомлением. Запуск (из папки backend): python ../tools/seed_demo.py community.db

Вход в приложении: demo@vyborvkusa.test / demo12345
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))

from app.auth import AuthStore, RegisterIn  # noqa: E402
from app.community import CommunityStore, PublishIn, RatingIn, open_db  # noqa: E402
from app.notifications import NotificationStore  # noqa: E402


def user(auth, email, name):
    u, _ = auth.register(RegisterIn(email=email, password="demo12345", display_name=name))
    return auth.mark_email_verified(u["id"])


def main(path: str) -> None:
    db = open_db(path)
    community = CommunityStore(db)
    auth = AuthStore(db)
    notes = NotificationStore(db)
    demo = user(auth, "demo@vyborvkusa.test", "Демо")
    chef = user(auth, "chef@vyborvkusa.test", "Шеф Ольга")

    carbonara = PublishIn.model_validate({
        "name": "Карбонара по-римски",
        "recipe": {"id": "carbonara", "title": "Паста карбонара", "summary": "", "servings": 2, "steps": [],
                   "ingredients": [
                       {"id": "carbonara-pasta", "title": "Спагетти", "category_id": "spaghetti", "amount": 200, "unit": "g"},
                       {"id": "carbonara-cheese", "title": "Твёрдый сыр", "category_id": "hard-cheese", "amount": 60, "unit": "g"},
                   ]},
        "items": [
            {"ingredient_id": "carbonara-pasta", "product": {"id": "spaghetti-barilla", "name": "Спагетти №5",
                                                             "brand": "Barilla", "category_id": "spaghetti"}},
            {"ingredient_id": "carbonara-cheese", "product": {"id": "pecorino", "name": "Пекорино Романо",
                                                              "category_id": "hard-cheese"}},
        ],
    })
    olga = community.publish(chef["id"], chef["display_name"], carbonara)

    pie = PublishIn.model_validate({
        "name": "Бабушкин пирог",
        "recipe": {"id": "user-demo-pie", "title": "Яблочный пирог бабушки Оли", "summary": "Без миксера, за час.",
                   "servings": 6, "steps": ["Смешайте яйца с сахаром.", "Добавьте муку и яблоки.",
                                            "Выпекайте 40 минут при 180 °C."],
                   "rubric": "pastry", "cook_minutes": 60,
                   "ingredients": [
                       {"id": "pie-eggs", "title": "Яйца", "category_id": "eggs", "amount": 3, "unit": "pcs"},
                       {"id": "pie-apples", "title": "Яблоки", "category_id": "apples", "amount": 500, "unit": "g"},
                   ]},
        "items": [
            {"ingredient_id": "pie-eggs", "product": {"id": "eggs-c0", "name": "Яйца С0", "category_id": "eggs"}},
            {"ingredient_id": "pie-apples", "product": {"id": "user-p-antonovka", "name": "Антоновка с дачи",
                                                        "category_id": "apples"}},
        ],
    })
    community.publish(chef["id"], chef["display_name"], pie)

    mine = community.publish(demo["id"], demo["display_name"], carbonara.model_copy(update={"name": "Моя карбонара"}))
    community.rate(mine["id"], chef["id"], chef["display_name"], RatingIn(stars=5, comment="Отличный выбор сыра!"))
    notes.add(demo["id"], "comment", mine["id"], mine["name"], chef["id"], chef["display_name"], 5,
              "Отличный выбор сыра!")
    community.rate(olga["id"], demo["id"], demo["display_name"], RatingIn(stars=4, comment=None))
    print("seeded:", demo["email"], chef["email"])


if __name__ == "__main__":
    main(sys.argv[1])
