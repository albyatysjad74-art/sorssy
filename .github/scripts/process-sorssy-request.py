#!/usr/bin/env python3
"""Validate owner-submitted sorssy issues and update the app source/catalog."""
import hashlib
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse

OWNER = "albyatysjad74-art"
SOURCE_PATH = Path("iQsign-Apps-Source.json")
CATALOG_PATH = Path("sorssy-sources.json")


def set_output(key: str, value: str) -> None:
    value = str(value).replace("\r", " ").replace("\n", " ")
    output_path = os.environ.get("GITHUB_OUTPUT")
    if output_path:
        with open(output_path, "a", encoding="utf-8") as f:
            f.write(f"{key}={value}\n")


def result(status: str, message: str, changed: bool = False) -> None:
    set_output("status", status)
    set_output("message", message)
    set_output("changed", "true" if changed else "false")


def text_field(data: dict, key: str, *, required: bool = False, limit: int = 5000, multiline: bool = False) -> str:
    value = data.get(key, "")
    if not isinstance(value, str):
        raise ValueError(f"الحقل {key} لازم يكون نصًا.")
    value = value.strip()
    if required and not value:
        raise ValueError(f"الحقل {key} مطلوب.")
    if len(value) > limit:
        raise ValueError(f"قيمة الحقل {key} أطول من المسموح.")
    if any(ord(ch) < 32 and ch not in ("\n\t" if multiline else "") for ch in value):
        raise ValueError(f"قيمة الحقل {key} تحتوي محارف غير مسموحة.")
    return value


def https_url(data: dict, key: str, *, required: bool = True) -> str:
    value = text_field(data, key, required=required, limit=2048)
    if not value and not required:
        return ""
    parsed = urlparse(value)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
        raise ValueError(f"رابط {key} لازم يكون رابط HTTPS صالحًا.")
    return value


def valid_bundle_id(value: str) -> bool:
    return bool(re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", value))


def read_event() -> tuple[dict, dict]:
    path = os.environ.get("EVENT_PATH") or os.environ.get("GITHUB_EVENT_PATH")
    if not path:
        raise ValueError("بيانات الحدث غير متوفرة.")
    event = json.loads(Path(path).read_text(encoding="utf-8"))
    issue = event.get("issue") or {}
    if (issue.get("user") or {}).get("login") != OWNER:
        raise ValueError("هذا النموذج مخصص لصاحب المستودع فقط.")
    if (event.get("sender") or {}).get("login") != OWNER:
        raise ValueError("يجب أن ينفذ الطلب صاحب المستودع بنفسه.")
    if not str(issue.get("title", "")).startswith("[Sorssy]"):
        raise ValueError("عنوان الطلب غير صحيح. أرسل الطلب من صفحة sorssy.")
    body = issue.get("body") or ""
    if not isinstance(body, str):
        raise ValueError("محتوى الطلب غير صالح.")
    try:
        data = json.loads(body.strip())
    except json.JSONDecodeError as exc:
        raise ValueError("تعذّرت قراءة بيانات الطلب. أعد الإرسال من نموذج sorssy.") from exc
    if not isinstance(data, dict):
        raise ValueError("صيغة بيانات الطلب غير صحيحة.")
    return issue, data


def read_source() -> tuple[dict, list]:
    source = json.loads(SOURCE_PATH.read_text(encoding="utf-8"))
    apps = source.get("apps")
    if not isinstance(apps, list):
        raise ValueError("ملف السورس لا يحتوي قائمة تطبيقات صالحة.")
    return source, apps


def parse_app_fields(data: dict, *, existing_bundle: str | None = None) -> dict:
    name = text_field(data, "name", required=True, limit=100)
    bundle_id = text_field(data, "bundleIdentifier", required=True, limit=150)
    if not valid_bundle_id(bundle_id) and bundle_id != existing_bundle:
        raise ValueError("معرّف الحزمة غير صحيح؛ استخدم صيغة مثل com.example.app.")
    version = text_field(data, "version", required=True, limit=50)
    category = text_field(data, "category", limit=50) or "أخرى"
    icon_url = https_url(data, "iconURL")
    download_url = https_url(data, "downloadURL")
    description = text_field(data, "localizedDescription", limit=5000, multiline=True)
    size = data.get("size")
    if size in (None, ""):
        size = None
    elif isinstance(size, bool) or not isinstance(size, (int, float)) or size <= 0 or size > 1_000_000_000_000:
        raise ValueError("حجم التطبيق غير صالح.")
    else:
        size = int(size)
    return {"name": name, "bundleIdentifier": bundle_id, "version": version, "category": category,
            "iconURL": icon_url, "downloadURL": download_url, "localizedDescription": description, "size": size}


def add_app(data: dict) -> None:
    parsed = parse_app_fields(data)
    source, apps = read_source()
    if any(a.get("downloadURL") == parsed["downloadURL"] for a in apps):
        result("duplicate", "رابط التنزيل موجود مسبقًا في السورس؛ لم تتم إضافة نسخة مكررة.")
        return
    now = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    version_item = {"downloadURL": parsed["downloadURL"], "version": parsed["version"], "date": now}
    app = {k: parsed[k] for k in ("name", "bundleIdentifier", "iconURL", "category", "version", "downloadURL")}
    app.update({"versionDate": now, "versions": [version_item]})
    if parsed["size"] is not None:
        app["size"] = parsed["size"]
        version_item["size"] = parsed["size"]
    if parsed["localizedDescription"]:
        app["localizedDescription"] = parsed["localizedDescription"]
    apps.append(app)
    SOURCE_PATH.write_text(json.dumps(source, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    result("added", f"تمت إضافة {parsed['name']} إلى السورس.", True)


def find_target(apps: list, target: dict) -> tuple[int, dict]:
    if not isinstance(target, dict):
        raise ValueError("ما قدرنا نحدد التطبيق المطلوب تعديله.")
    keys = ("name", "bundleIdentifier", "version", "downloadURL", "iconURL")
    index = target.get("index")
    if isinstance(index, int) and not isinstance(index, bool) and 0 <= index < len(apps):
        candidate = apps[index]
        if all(candidate.get(k) == target.get(k) for k in keys if k in target):
            return index, candidate
    matches = [(i, a) for i, a in enumerate(apps) if all(a.get(k) == target.get(k) for k in keys if k in target)]
    if len(matches) == 1:
        return matches[0]
    if not matches:
        raise ValueError("لم نعد نجد التطبيق بنفس البيانات؛ حدّث الصفحة وافتحه من جديد.")
    raise ValueError("تعذر التمييز بين نسخ التطبيق. حدّث الصفحة ثم جرّب من جديد.")


def edit_app(data: dict) -> None:
    source, apps = read_source()
    index, app = find_target(apps, data.get("target"))
    before = json.dumps(app, ensure_ascii=False, sort_keys=True)
    changes = parse_app_fields(data.get("changes") or {}, existing_bundle=app.get("bundleIdentifier"))
    now = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    changed_version = app.get("version") != changes["version"] or app.get("downloadURL") != changes["downloadURL"]
    for key in ("name", "bundleIdentifier", "version", "category", "iconURL", "downloadURL"):
        app[key] = changes[key]
    if changes["localizedDescription"]:
        app["localizedDescription"] = changes["localizedDescription"]
    else:
        app.pop("localizedDescription", None)
    if changes["size"] is None:
        app.pop("size", None)
    else:
        app["size"] = changes["size"]
    if changed_version:
        app["versionDate"] = now
        versions = app.get("versions")
        if not isinstance(versions, list):
            versions = []
        version_item = {"downloadURL": changes["downloadURL"], "version": changes["version"], "date": now}
        if changes["size"] is not None:
            version_item["size"] = changes["size"]
        if not any(v.get("version") == changes["version"] and v.get("downloadURL") == changes["downloadURL"] for v in versions if isinstance(v, dict)):
            versions.insert(0, version_item)
        app["versions"] = versions
    if json.dumps(app, ensure_ascii=False, sort_keys=True) == before:
        result("unchanged", "لم تتغير أي بيانات؛ لا حاجة لتحديث السورس.")
        return
    SOURCE_PATH.write_text(json.dumps(source, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    result("edited", f"تم حفظ تعديلات {changes['name']} في السورس.", True)


def add_source(data: dict) -> None:
    item = data.get("source")
    if not isinstance(item, dict):
        raise ValueError("بيانات المصدر غير صالحة.")
    name = text_field(item, "name", required=True, limit=100)
    subtitle = text_field(item, "subtitle", limit=200)
    url = https_url(item, "url")
    icon_url = https_url(item, "iconURL", required=False)
    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    sources = catalog.get("sources")
    if not isinstance(sources, list):
        raise ValueError("قائمة المصادر غير صالحة.")
    if any(s.get("url", "").rstrip("/") == url.rstrip("/") for s in sources):
        result("duplicate", "هذا المصدر مضاف مسبقًا في القائمة.")
        return
    source_id = "ext-" + hashlib.sha256(url.encode("utf-8")).hexdigest()[:12]
    sources.append({"id": source_id, "name": name, "subtitle": subtitle, "iconURL": icon_url, "url": url, "editable": False})
    CATALOG_PATH.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    result("source_added", f"تمت إضافة مصدر {name} إلى قائمة sorssy.", True)


def main() -> None:
    issue, data = read_event()
    title = str(issue.get("title", ""))
    if title.startswith("[Sorssy] إضافة تطبيق:") and data.get("action") == "add_app":
        add_app(data)
    elif title.startswith("[Sorssy] تعديل تطبيق:") and data.get("action") == "edit_app":
        edit_app(data)
    elif title.startswith("[Sorssy] إضافة مصدر:") and data.get("action") == "add_source":
        add_source(data)
    else:
        raise ValueError("نوع الطلب غير معروف. أعده من لوحة sorssy.")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        result("invalid", str(exc))
        print(f"Request rejected: {exc}", file=sys.stderr)
