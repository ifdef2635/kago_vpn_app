#!/usr/bin/env python3
"""Анонс релиза KaGo VPN в Telegram.

Идея и формат сообщения — из FlClashX (.github/scripts/notify_telegram.py),
но без внешних зависимостей (только stdlib: на раннере не нужен pip) и со
списком каналов в одном секрете TELEGRAM_CHAT_IDS через запятую.

Переменные окружения:
  TELEGRAM_BOT_TOKEN — токен бота (обязателен);
  TELEGRAM_CHAT_IDS  — получатели через запятую (@channel или -100…);
  VERSION            — версия релиза (например 2.0.4);
  RELEASE_URL        — ссылка на страницу релиза;
  NOTES              — «Что нового» (Markdown из RELEASE_STATUS.md);
  PRERELEASE         — 'true', если это предварительный релиз.

parse_mode=HTML: в заголовках коммитов и заметках хватает символов, на
которых падает разбор Markdown («_», «*»), а в HTML достаточно экранировать
& < > — поэтому все подставляемые части проходят через html.escape.
"""
import html
import json
import os
import re
import sys
import urllib.error
import urllib.request

API = 'https://api.telegram.org/bot{token}/sendMessage'
# Больше в одно сообщение Telegram не принимает (4096 символов с разметкой).
MAX_NOTES = 2500


def send(token: str, chat_id: str, text: str) -> bool:
    payload = json.dumps({
        'chat_id': chat_id,
        'text': text,
        'parse_mode': 'HTML',
        'disable_web_page_preview': False,
    }).encode()
    request = urllib.request.Request(
        API.format(token=token),
        data=payload,
        headers={'Content-Type': 'application/json'},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return 200 <= response.status < 300
    except urllib.error.HTTPError as error:
        # Текст ошибки Telegram полезен (неверный chat_id, бот не в канале),
        # токена в нём нет.
        print(f'  ошибка {error.code}: {error.read().decode(errors="replace")[:300]}')
    except urllib.error.URLError as error:
        print(f'  сеть недоступна: {error.reason}')
    return False


def clean_notes(markdown: str) -> str:
    """«Что нового» в вид, пригодный для Telegram: без разметки, списки — «•»."""
    text = markdown.replace('\r', '')
    # Служебные строки пользователю в канале не нужны.
    text = re.sub(r'(?im)^[\s*_]*(?:Платформы|Platforms)[\s*_]*:.*$', '', text)
    text = re.sub(r'(?ms)^Для разработчиков.*', '', text)
    text = re.sub(r'(?m)^#+\s*', '', text)
    text = text.replace('**', '').replace('`', '')
    text = re.sub(r'(?m)^(\s*)[-*]\s+', r'\1• ', text)
    text = re.sub(r'\n{3,}', '\n\n', text)
    return text.strip()


def main() -> int:
    token = os.environ.get('TELEGRAM_BOT_TOKEN', '').strip()
    chats = [c.strip() for c in os.environ.get('TELEGRAM_CHAT_IDS', '').split(',') if c.strip()]
    version = os.environ.get('VERSION', '').strip().lstrip('v')
    url = os.environ.get('RELEASE_URL', '').strip()
    notes = clean_notes(os.environ.get('NOTES', ''))
    prerelease = os.environ.get('PRERELEASE', 'false').lower() == 'true'

    if not token or not chats:
        # Секретов нет — анонс просто не нужен, это не ошибка сборки.
        print('TELEGRAM_BOT_TOKEN или TELEGRAM_CHAT_IDS не заданы — анонс пропущен.')
        return 0
    if not version or not url:
        print('::error::Не переданы VERSION или RELEASE_URL.')
        return 1

    if len(notes) > MAX_NOTES:
        notes = notes[:MAX_NOTES].rstrip() + '…'

    head = '🚀 Предварительная сборка' if prerelease else '🎉 Новая версия'
    message = f'{head} <b>KaGo VPN {html.escape(version)}</b>\n\n'
    if notes:
        message += f'<b>Что нового:</b>\n{html.escape(notes)}\n\n'
    message += f'🔗 <a href="{html.escape(url)}">Скачать на GitHub</a>'
    if not prerelease:
        message += '\n💡 В приложении: «Настройки → Обновление».'

    print(f'Анонс KaGo VPN {version} ({"pre-release" if prerelease else "stable"}) → {len(chats)} получателям.')
    failed = 0
    for chat in chats:
        print(f'отправка в {chat}…')
        if send(token, chat, message):
            print('  отправлено')
        else:
            print(f'::warning::Не удалось отправить анонс в {chat}.')
            failed += 1
    if failed == len(chats):
        print('::error::Анонс не доставлен ни одному получателю.')
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
