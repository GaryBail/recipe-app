# Сервер приложения: API, сообщество, цены магазинов (Лента, Магнит, Ашан, ВкусВилл, Купер).
# Браузер больше не нужен: все магазины отвечают на обычные HTTP-запросы.
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN useradd --create-home --uid 1000 app && mkdir -p /data /app && chown app:app /data /app

WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt

USER app
COPY --chown=app:app app ./app

ENV COMMUNITY_DB=/data/community.db \
    MEDIA_DIR=/data/media
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=4)"

# Ровно один процесс: в нём работает расписание проверки цен, а SQLite и лимиты попыток
# рассчитаны на одного писателя. Не увеличивайте --workers.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
