#!/usr/bin/env python3
"""外国の祝日表（holidays-XX.txt）を python-holidays から作る（#165）。

使い方:
    python3 -m venv /tmp/hv && /tmp/hv/bin/pip install holidays==0.107
    /tmp/hv/bin/python scripts/gen_holidays.py

作るもの（形式はどれも「年/月/日,名称」。# で始まる行は注記）:
- Ourin/Resources/Holidays/holidays-XX.txt: その国の既定の言語での祝日名（言語フォルダに表が無いときに使う）
- Ourin/en.lproj/holidays-XX.txt: 既定の言語が英語でない国の、英語の祝日名（表示が英語のとき）
- Ourin/Resources/Holidays/holidays-JP.txt: 内閣府の表はそのまま使い、
  - 「休日」を振替休日（日曜の祝日の翌日以降）と国民の休日（祝日に挟まれた日）に分ける
  - 内閣府の表の最後の年より後は、python-holidays の日本語名で足す
python-holidays は MIT ライセンス（Ourin/Resources/Licenses/Holidays_python-holidays.txt）。
"""

from __future__ import annotations

import datetime as dt
import pathlib
import warnings

import holidays

ROOT = pathlib.Path(__file__).resolve().parent.parent
HOLIDAYS_DIR = ROOT / "Ourin" / "Resources" / "Holidays"
ENGLISH_DIR = ROOT / "Ourin" / "en.lproj"
FIRST_YEAR = 2020
LAST_YEAR = 2050
SOURCE = f"python-holidays {holidays.__version__}（MIT ライセンス。https://github.com/vacanza/holidays）"
SOURCE_EN = f"python-holidays {holidays.__version__} (MIT License, https://github.com/vacanza/holidays)"


def years_for(code: str) -> range:
    probe = holidays.country_holidays(code)
    start = max(FIRST_YEAR, getattr(probe, "start_year", FIRST_YEAR))
    end = min(LAST_YEAR, getattr(probe, "end_year", LAST_YEAR))
    return range(start, end + 1)


def entries(code: str, language: str | None, years: range) -> list[tuple[dt.date, str]]:
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        table = holidays.country_holidays(code, years=years, language=language)
    result = []
    for day, name in sorted(table.items()):
        name = " ".join(str(name).split())
        # UKADOC の例（Christmas Day (substitute day)）と英国政府の表記に合わせる。
        if code == "GB":
            name = name.replace(" (observed)", " (substitute day)")
        result.append((day, name))
    return result


def write(path: pathlib.Path, header: list[str], rows: list[tuple[dt.date, str]]) -> None:
    lines = [f"# {line}" for line in header]
    lines += [f"{day.year}/{day.month}/{day.day},{name}" for day, name in rows]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def english_language(languages: tuple[str, ...]) -> str | None:
    for preferred in ("en_US", "en_GB"):
        if preferred in languages:
            return preferred
    return next((language for language in languages if language.startswith("en")), None)


def generate_countries() -> None:
    codes = sorted(code for code in holidays.list_supported_countries() if len(code) == 2 and code != "JP")
    for code in codes:
        probe = holidays.country_holidays(code)
        default = probe.default_language
        years = years_for(code)
        if len(years) == 0:
            continue
        rows = entries(code, default, years)
        if not rows:
            continue
        write(HOLIDAYS_DIR / f"holidays-{code}.txt",
              [f"{code} の祝日（{years.start}〜{years.stop - 1}年、言語: {default or 'en'}）", f"出典: {SOURCE}",
               "形式: 年/月/日,名称"], rows)
        english = english_language(tuple(probe.supported_languages or ()))
        if default and not default.startswith("en") and english:
            write(ENGLISH_DIR / f"holidays-{code}.txt",
                  [f"{code} holidays ({years.start}-{years.stop - 1}, language: {english})", f"Source: {SOURCE_EN}",
                   "Format: year/month/day,name"], entries(code, english, years))


def generate_japan() -> None:
    path = HOLIDAYS_DIR / "holidays-JP.txt"
    original = path.read_text(encoding="utf-8").splitlines()
    header = [line for line in original if line.startswith("#")]
    official: dict[dt.date, str] = {}
    for line in original:
        if line.startswith("#") or "," not in line:
            continue
        date_part, name = line.split(",", 1)
        parts = date_part.split("/")
        if len(parts) != 3 or not all(part.strip().isdigit() for part in parts):
            continue
        official[dt.date(*(int(part) for part in parts))] = name.strip()
    last_official_year = max(day.year for day in official)

    # 内閣府の表は振替休日と国民の休日をどちらも「休日」と書くので、分ける。
    def is_holiday(day: dt.date) -> bool:
        return day in official

    named: dict[dt.date, str] = {}
    for day, name in official.items():
        if name == "休日":
            cursor = day - dt.timedelta(days=1)
            substitute = False
            while is_holiday(cursor) and official[cursor] != "休日":
                if cursor.weekday() == 6:  # 日曜の祝日
                    substitute = True
                    break
                cursor -= dt.timedelta(days=1)
            name = "振替休日" if substitute else "国民の休日"
        named[day] = name

    extra = entries("JP", "ja", range(last_official_year + 1, LAST_YEAR + 1))
    for day, name in extra:
        named.setdefault(day, name)

    new_header = [line for line in header if not line.startswith("# 形式")]
    new_header += [
        f"# {last_official_year + 1}〜{LAST_YEAR}年は {SOURCE} の日本語名で補った。",
        "# 内閣府の表の「休日」は、振替休日（日曜の祝日の翌日以降）と国民の休日（祝日に挟まれた日）に分けた。",
        "# 形式: 年/月/日,名称。# で始まる行と、日付で始まらない行は無視する。",
    ]
    lines = new_header + [f"{day.year}/{day.month}/{day.day},{name}" for day, name in sorted(named.items())]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    years = years_for("JP")
    write(ENGLISH_DIR / "holidays-JP.txt",
          [f"JP holidays ({years.start}-{years.stop - 1}, language: en_US)", f"Source: {SOURCE_EN}",
           "Format: year/month/day,name"], entries("JP", "en_US", years))


if __name__ == "__main__":
    generate_countries()
    generate_japan()
