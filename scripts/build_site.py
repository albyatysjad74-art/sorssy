#!/usr/bin/env python3
"""Validate sorssy and assemble a dependency-free static site package."""
from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
OWNER = "albyatysjad74-art"
REPO = "sorssy"
RAW_SOURCE = f"https://raw.githubusercontent.com/{OWNER}/{REPO}/main/iQsign-Apps-Source.json"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def is_https_url(value: object) -> bool:
    if not isinstance(value, str):
        return False
    parsed = urlparse(value)
    return parsed.scheme == "https" and bool(parsed.hostname) and not parsed.username and not parsed.password


def check_javascript(html: str) -> None:
    scripts = re.findall(r"<script\b[^>]*>(.*?)</script\s*>", html, flags=re.IGNORECASE | re.DOTALL)
    require(bool(scripts), "لم يتم العثور على شيفرة JavaScript في index.html.")
    node = shutil.which("node")
    require(node is not None, "Node.js مطلوب لفحص صياغة JavaScript.")
    for script in scripts:
        if not script.strip():
            continue
        with tempfile.NamedTemporaryFile("w", suffix=".js", encoding="utf-8", delete=False) as temp:
            temp.write(script)
            temp_path = Path(temp.name)
        try:
            checked = subprocess.run([node, "--check", str(temp_path)], capture_output=True, text=True)
            require(checked.returncode == 0, f"فشل فحص JavaScript: {checked.stderr.strip()}")
        finally:
            temp_path.unlink(missing_ok=True)


def load_and_validate() -> tuple[dict, dict, str]:
    html_path = ROOT / "index.html"
    source_path = ROOT / "iQsign-Apps-Source.json"
    catalog_path = ROOT / "sorssy-sources.json"
    require(html_path.is_file(), "ملف index.html غير موجود.")
    require(source_path.is_file(), "ملف iQsign-Apps-Source.json غير موجود.")
    require(catalog_path.is_file(), "ملف sorssy-sources.json غير موجود.")

    html = html_path.read_text(encoding="utf-8")
    require('<html lang="ar" dir="rtl">' in html, "يجب أن تبقى واجهة الموقع عربية ومن اليمين إلى اليسار.")
    require(f"const OWNER='{OWNER}', REPO='{REPO}'" in html, "إعدادات المستودع في لوحة الإدارة غير صحيحة.")
    check_javascript(html)

    source = json.loads(source_path.read_text(encoding="utf-8"))
    require(isinstance(source, dict) and isinstance(source.get("apps"), list), "ملف السورس يجب أن يحتوي قائمة apps.")
    for number, app in enumerate(source["apps"], start=1):
        require(isinstance(app, dict), f"بيانات التطبيق رقم {number} غير صالحة.")
        for key in ("name", "bundleIdentifier", "version"):
            require(isinstance(app.get(key), str) and bool(app[key].strip()), f"التطبيق رقم {number}: الحقل {key} مطلوب.")
        for key in ("iconURL", "downloadURL"):
            require(is_https_url(app.get(key)), f"التطبيق رقم {number}: الحقل {key} يجب أن يكون رابط HTTPS صالحًا.")

    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    require(isinstance(catalog, dict) and isinstance(catalog.get("sources"), list), "قائمة المصادر غير صالحة.")
    for number, source_item in enumerate(catalog["sources"], start=1):
        require(isinstance(source_item, dict), f"المصدر رقم {number} غير صالح.")
        require(isinstance(source_item.get("name"), str) and bool(source_item["name"].strip()), f"المصدر رقم {number}: الاسم مطلوب.")
        require(is_https_url(source_item.get("url")), f"المصدر رقم {number}: الرابط يجب أن يكون HTTPS صالحًا.")
        require(isinstance(source_item.get("editable"), bool), f"المصدر رقم {number}: حالة التحرير غير صالحة.")
    editable = [item for item in catalog["sources"] if item.get("editable")]
    require(len(editable) == 1 and editable[0].get("url") == RAW_SOURCE,
            "يجب أن يكون مصدر sorssy المملوك هو المصدر الوحيد القابل للتحرير.")
    return source, catalog, html


def build(output: Path) -> None:
    source, catalog, _ = load_and_validate()
    output.mkdir(parents=True, exist_ok=True)
    for filename in ("index.html", "iQsign-Apps-Source.json", "sorssy-sources.json"):
        shutil.copy2(ROOT / filename, output / filename)
    build_info = {
        "name": "sorssy",
        "kind": "static-site",
        "applicationCount": len(source["apps"]),
        "sourceCount": len(catalog["sources"]),
        "files": ["index.html", "iQsign-Apps-Source.json", "sorssy-sources.json"],
        "publishUrl": "https://albyatysjad74-art.github.io/sorssy/",
    }
    (output / "build-info.json").write_text(json.dumps(build_info, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"بناء ناجح: {len(source['apps'])} تطبيق، {len(catalog['sources'])} مصدر، الحزمة: {output}")


if __name__ == "__main__":
    destination = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / "dist"
    if destination == ROOT:
        raise SystemExit("ممنوع إخراج الحزمة فوق ملفات المشروع.")
    try:
        build(destination)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"فشل البناء: {exc}", file=sys.stderr)
        raise SystemExit(1)
