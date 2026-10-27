"""Отправка писем: коды подтверждения email и восстановления пароля.

Если SMTP не настроен, письма пишутся в лог сервера — удобно при разработке.
"""

from __future__ import annotations

import asyncio
import logging
import os
import smtplib
import ssl
from email.message import EmailMessage
from typing import Protocol

log = logging.getLogger(__name__)


class Mailer(Protocol):
    async def send(self, to: str, subject: str, text: str) -> None: ...


class ConsoleMailer:
    async def send(self, to: str, subject: str, text: str) -> None:
        log.warning("Письмо для %s (SMTP не настроен)\n%s\n%s", to, subject, text)


class SMTPMailer:
    def __init__(self, host: str, port: int, user: str | None, password: str | None, sender: str):
        self.host, self.port, self.user, self.password, self.sender = host, port, user, password, sender

    def _send_sync(self, msg: EmailMessage) -> None:
        context = ssl.create_default_context()
        if self.port == 465:
            with smtplib.SMTP_SSL(self.host, self.port, context=context, timeout=15) as s:
                if self.user:
                    s.login(self.user, self.password or "")
                s.send_message(msg)
        else:
            with smtplib.SMTP(self.host, self.port, timeout=15) as s:
                s.starttls(context=context)
                if self.user:
                    s.login(self.user, self.password or "")
                s.send_message(msg)

    async def send(self, to: str, subject: str, text: str) -> None:
        msg = EmailMessage()
        msg["From"] = self.sender
        msg["To"] = to
        msg["Subject"] = subject
        msg.set_content(text)
        try:
            await asyncio.to_thread(self._send_sync, msg)
        except Exception:
            log.exception("Не удалось отправить письмо на %s", to)


def mailer_from_env() -> Mailer:
    host = os.getenv("SMTP_HOST")
    if not host:
        return ConsoleMailer()
    return SMTPMailer(host=host, port=int(os.getenv("SMTP_PORT", "465")), user=os.getenv("SMTP_USER"),
                      password=os.getenv("SMTP_PASSWORD"), sender=os.getenv("SMTP_FROM", os.getenv("SMTP_USER", "")))


def code_email(purpose: str, code: str, name: str) -> tuple[str, str]:
    if purpose == "reset":
        return ("Код для восстановления пароля",
                f"{name}, ваш код для восстановления пароля: {code}\n\n"
                "Код действует 15 минут. Если вы не запрашивали восстановление — просто проигнорируйте письмо.")
    return ("Подтвердите email",
            f"{name}, ваш код подтверждения: {code}\n\n"
            "Введите его в приложении. Код действует 15 минут.")
