# Сервер приложения: API, сообщество, цены магазинов (через браузер Camoufox).
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# git — для установки библиотек магазинов из GitHub; xvfb — виртуальный экран для браузера.
RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates xvfb \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
# Системные библиотеки Firefox ставим через playwright (он приходит вместе с camoufox).
RUN pip install -r requirements.txt \
    && python -m playwright install-deps firefox \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --uid 1000 app && mkdir -p /data && chown app:app /data
USER app
# Браузер Camoufox и база GeoIP скачиваются в домашнюю папку пользователя app.
RUN python -m camoufox fetch

COPY --chown=app:app app ./app

ENV COMMUNITY_DB=/data/community.db \
    HEADLESS=virtual
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=4)"

# Ровно один процесс: в нём работает расписание проверки цен, а SQLite и лимиты попыток
# рассчитаны на одного писателя. Не увеличивайте --workers.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
