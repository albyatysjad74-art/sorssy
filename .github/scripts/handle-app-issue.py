#!/usr/bin/env python3
"""Validate an owner-submitted GitHub issue and append one app to the source JSON."""
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse

OWNER = "albyatysjad74-art"
TITLE_PREFIX = "[Sorssy] إضافة تطبيق:"
SOURCE = Path("iQsign-Apps-Source.json")


def set_output(key: str, value: str) -> None:
    """Write a single-line GitHub Actions output safely."""
    value = value.replace("\r", " ").replace("\n", " ")
    output_path = os.environ.get("GITHUB_OUTPUT")
    if output_path:
        with open(output_path, "a", encoding="utf-8") as f:
            f.write(f"{key}={value}\n")


def result(status: str, message: str) -> None:
    set_output("status", status)
    set_output("message", message)


def text_field(data: dict, key: str, *, required: bool = False, limit: int = 5000) -> str:
    value = data.get(key, "")
    if not isinstance(value, str):
        raise ValueError(f"الحقل {key} لازم يكون نصًا.")
    value = value.strip()
    if required and not value:
        raise ValueError(f"الحقل {key} مطلوب.")
    if len(value) > limit:
        raise ValueError(f"قيمة الحقل {key} أطول من المسموح.")
    if any(ord(ch) < 32 and ch not in "\n\t" for ch in value):
        raise ValueError(f"قيمة الحقل {key} تحتوي محارف غير مسموحة.")
    return value


def https_url(data: dict, key: str) -> str:
    value = text_field(data, key, required=True, limit=2048)
    parsed = urlparse(value)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
        raise ValueError(f"رابط {key} لازم يكون رابط HTTPS صالحًا.")
    return value


def main() -> None:
    event_path = os.environ.get("EVENT_PATH") or os.environ.get("GITHUB_EVENT_PATH")
    if not event_path:
        raise ValueError("بيانات الحدث غير متوفرة.")
    event = json.loads(Path(event_path).read_text(encoding="utf-8"))
    issue = event.get("issue") or {}
    if (issue.get("user") or {}).get("login") != OWNER:
        result("invalid", "هذا النموذج مخصص لصاحب المستودع فقط.")
        return
    if not str(issue.get("title", "")).startswith(TITLE_PREFIX):
        result("invalid", "عنوان الطلب غير صحيح. أرسل الطلب من صفحة sorssy.")
        return

    body = issue.get("body") or ""
    if not isinstance(body, str):
        raise ValueError("محتوى الطلب غير صالح.")
    try:
        data = json.loads(body.strip())
    except json.JSONDecodeError as exc:
        raise ValueError("تعذّرت قراءة بيانات الطلب. أعد الإرسال من نموذج sorssy.") from exc
    if not isinstance(data, dict):
        raise ValueError("صيغة بيانات الطلب غير صحيحة.")

    name = text_field(data, "name", required=True, limit=100)
    bundle_id = text_field(data, "bundleIdentifier", required=True, limit=150)
    if not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", bundle_id):
        raise ValueError("معرّف الحزمة غير صحيح؛ استخدم صيغة مثل com.example.app.")
    version = text_field(data, "version", required=True, limit=50)
    category = text_field(data, "category", limit=50) or "أخرى"
    icon_url = https_url(data, "iconURL")
    download_url = https_url(data, "downloadURL")
    description = text_field(data, "localizedDescription", limit=5000)

    size = data.get("size")
    if size not in (None, ""):
        if isinstance(size, bool) or not isinstance(size, (int, float)) or size <= 0 or size > 1_000_000_000_000:
            raise ValueError("حجم التطبيق غير صالح.")
        size = int(size)
    else:
        size = None

    source = json.loads(SOURCE.read_text(encoding="utf-8"))
    apps = source.get("apps")
    if not isinstance(apps, list):
        raise ValueError("ملف السورس لا يحتوي قائمة تطبيقات صالحة.")

    for current in apps:
        if current.get("downloadURL") == download_url:
            result("duplicate", "رابط التنزيل موجود مسبقًا في السورس؛ لم تتم إضافة نسخة مكررة.")
            return

    now = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    version_item = {"downloadURL": download_url, "version": version, "date": now}
    app = {
        "name": name,
        "bundleIdentifier": bundle_id,
        "iconURL": icon_url,
        "category": category,
        "version": version,
        "downloadURL": download_url,
        "versionDate": now,
        "versions": [version_item],
    }
    if size is not None:
        app["size"] = size
        version_item["size"] = size
    if description:
        app["localizedDescription"] = description

    apps.append(app)
    SOURCE.write_text(json.dumps(source, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    result("added", f"تمت إضافة {name} إلى السورس.")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        result("invalid", str(exc))
        print(f"Submission rejected: {exc}", file=sys.stderr)
