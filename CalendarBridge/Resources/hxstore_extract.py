#!/usr/bin/env python3
"""
CalendarBridge HxStore fallback extractor.

Adapted from reverse-engineering ideas used by the MIT-licensed hxstore-decode project.
This script intentionally uses only the Python standard library so it can run on macOS
without extra package installation.
"""

from __future__ import annotations

import json
import re
import struct
import sys
from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

PAGE_SIZE = 0x1000
SLOT_SIZE = 0x200
SLOT_HEADER_SIZE = 32
SLOT_DATA_SIZE = SLOT_SIZE - SLOT_HEADER_SIZE
DATA_PAGE_TYPE = 8
HXSTORE_MAGIC = b"Nostromoi"
DOTNET_SENTINEL = b"\xff\x3f\x37\xf4\x75\x28\xca\x2b"
DOTNET_TICKS_MIN = 633_979_008_000_000_000
DOTNET_TICKS_MAX = 642_297_024_000_000_000
DOTNET_TICKS_PER_SECOND = 10_000_000
REMINDER_OFFSET_MINUTES = 5
UTF16_RE = re.compile(rb"(?:[\x20-\x7e]\x00){3,}")
EMAIL_RE = re.compile(r"[\w.+-]+@[\w.]+\.\w{2,6}")

IGNORE_EXACT = {
    "Microsoft Teams Meeting",
    "Microsoft Teams meeting",
    "Join the meeting now",
    "For organizers: Meeting options",
    "huddle",
    "Microsoft Teams Need help?",
    "Need help?",
    "___",
    "________________________________",
    "Nehmen Sie von Ihrem Computer oder der mobilen App aus teil",
    "Klicken Sie hier, um an der Besprechung teilzunehmen",
    "W. Europe Standard Time",
    "Central Europe Standard Time",
    "Central European Standard Time",
    "Romance Standard Time",
    "UTC",
    "GMT",
    "Inbox",
}
IGNORE_PREFIXES = (
    "Meeting ID:",
    "Passcode:",
    "Join:",
    "http://",
    "https://",
)
CANCEL_PREFIXES = (
    "canceled:",
    "cancelled:",
    "accepted:",
    "declined:",
    "tentative:",
)
BAD_PHRASES = (
    "This meeting will take place",
    "As announced",
    "In addition to the global event",
    "Let's use this time",
    "Dear colleagues",
)
LOCATION_HINTS = (
    "DUS.",
    "PMI.",
    "MTR",
    "Bridge ",
    "Campus",
    "Room",
)


def main() -> int:
    args = json.loads(sys.stdin.read() or "{}")
    window_start = parse_iso(args.get("windowStart"))
    window_end = parse_iso(args.get("windowEnd"))
    requested_calendar_id = str(args.get("calendarID") or "")

    hxstore_path = find_hxstore(args.get("hxstorePath"))
    if hxstore_path is None:
        print(json.dumps({"events": [], "backend": "hxstore", "warning": "HxStore not found"}))
        return 0

    data = hxstore_path.read_bytes()
    if not data.startswith(HXSTORE_MAGIC):
        print(json.dumps({"events": [], "backend": "hxstore", "warning": "Invalid HxStore file"}))
        return 0

    primary_store_id, secondary_store_id = discover_store_ids(data)
    events = extract_events(
        data=data,
        primary_store_id=primary_store_id,
        secondary_store_id=secondary_store_id,
        requested_calendar_id=requested_calendar_id,
        window_start=window_start,
        window_end=window_end,
    )

    print(json.dumps({"events": events, "backend": "hxstore"}))
    return 0


def parse_iso(value: str | None) -> datetime:
    if not value:
        return datetime.now(timezone.utc)
    normalized = value.replace("Z", "+00:00")
    parsed = datetime.fromisoformat(normalized)
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def find_hxstore(explicit_path: str | None) -> Path | None:
    if explicit_path:
        path = Path(explicit_path).expanduser()
        return path if path.is_file() else None

    candidates = [
        Path.home() / "Library/Group Containers/UBF8T346G9.Office/Outlook/Outlook 15 Profiles/Main Profile/HxStore.hxd",
        Path.home() / "Library/Group Containers/UBF8T346G9.Office/Outlook/Outlook 15 Profiles/Main Profile/Data/Outlook.sqlite",
    ]

    hxstore = candidates[0]
    return hxstore if hxstore.is_file() else None


def discover_store_ids(data: bytes) -> tuple[bytes, bytes]:
    zero = b"\x00" * 8
    data_ids: Counter[bytes] = Counter()
    other_ids: Counter[bytes] = Counter()
    num_pages = len(data) // PAGE_SIZE

    for page_num in range(1, num_pages):
        offset = page_num * PAGE_SIZE
        store_id = data[offset + 8 : offset + 16]
        if store_id == zero:
            continue
        page_type = struct.unpack_from("<I", data, offset + 16)[0]
        if page_type == DATA_PAGE_TYPE:
            data_ids[store_id] += 1
        else:
            other_ids[store_id] += 1

    primary = data_ids.most_common(1)[0][0]
    secondary = next((sid for sid, _ in other_ids.most_common() if sid != primary), zero)
    return primary, secondary


def classify_page(data: bytes, page_num: int, primary_store_id: bytes, secondary_store_id: bytes) -> str:
    if page_num == 0:
        return "header"
    offset = page_num * PAGE_SIZE
    store_id = data[offset + 8 : offset + 16]
    page_type = struct.unpack_from("<I", data, offset + 16)[0]
    if store_id == primary_store_id and page_type == DATA_PAGE_TYPE:
        return "data"
    if store_id == secondary_store_id and secondary_store_id != b"\x00" * 8:
        return "index"
    return "blob"


def extract_events(
    data: bytes,
    primary_store_id: bytes,
    secondary_store_id: bytes,
    requested_calendar_id: str,
    window_start: datetime,
    window_end: datetime,
) -> list[dict[str, Any]]:
    num_pages = len(data) // PAGE_SIZE
    seen_offsets: set[int] = set()
    seen_keys: set[tuple[str, str]] = set()
    events: list[dict[str, Any]] = []

    for page_num in range(num_pages):
        if classify_page(data, page_num, primary_store_id, secondary_store_id) not in {"data", "index"}:
            continue

        skip_until = -1
        for slot_num in range(8):
            if slot_num <= skip_until:
                continue

            slot_offset = page_num * PAGE_SIZE + slot_num * SLOT_SIZE
            store_id = data[slot_offset + 8 : slot_offset + 16]
            record_type = struct.unpack_from("<I", data, slot_offset + 16)[0]
            size_a = struct.unpack_from("<I", data, slot_offset + 20)[0]
            size_b = struct.unpack_from("<I", data, slot_offset + 24)[0]

            if not (store_id == primary_store_id and record_type == DATA_PAGE_TYPE and size_a > 0):
                continue
            if slot_offset in seen_offsets:
                continue
            seen_offsets.add(slot_offset)

            raw = data[slot_offset + SLOT_HEADER_SIZE : slot_offset + SLOT_HEADER_SIZE + size_a]
            if len(raw) < 12:
                continue

            record_format = struct.unpack_from("<I", raw, 8)[0]
            if record_format != 400:
                if size_a > SLOT_DATA_SIZE:
                    total_bytes = SLOT_HEADER_SIZE + size_a
                    skip_until = slot_num + (total_bytes + SLOT_SIZE - 1) // SLOT_SIZE - 1
                continue

            record_id = extract_record_id(raw)
            decompressed = lz4_block_decompress_lenient(raw[8:], max(size_b - 8, 0))
            start_date = extract_display_time(decompressed)
            if start_date is None or start_date < window_start or start_date > window_end:
                if size_a > SLOT_DATA_SIZE:
                    total_bytes = SLOT_HEADER_SIZE + size_a
                    skip_until = slot_num + (total_bytes + SLOT_SIZE - 1) // SLOT_SIZE - 1
                continue

            start_date = corrected_start_date(start_date)

            strings = extract_utf16_strings(decompressed)
            subject, score = choose_subject(strings)
            if not subject or score < 4:
                if size_a > SLOT_DATA_SIZE:
                    total_bytes = SLOT_HEADER_SIZE + size_a
                    skip_until = slot_num + (total_bytes + SLOT_SIZE - 1) // SLOT_SIZE - 1
                continue

            if subject.lower().startswith(CANCEL_PREFIXES) or "@" in subject or EMAIL_RE.search(subject):
                if size_a > SLOT_DATA_SIZE:
                    total_bytes = SLOT_HEADER_SIZE + size_a
                    skip_until = slot_num + (total_bytes + SLOT_SIZE - 1) // SLOT_SIZE - 1
                continue

            dedupe_key = (subject, start_date.isoformat())
            if dedupe_key in seen_keys:
                continue
            seen_keys.add(dedupe_key)

            end_date = infer_end_date(subject, start_date)
            location = extract_location(strings, subject)
            notes = extract_notes(strings, subject)

            events.append(
                {
                    "recordID": str(record_id),
                    "sourceCalendarID": requested_calendar_id,
                    "sourceCalendarName": "Outlook HxStore",
                    "subject": subject,
                    "startDate": start_date.isoformat(),
                    "endDate": end_date.isoformat(),
                    "location": location,
                    "notes": notes,
                    "allDay": False,
                    "modificationDate": None,
                    "icalendarData": None,
                }
            )

            if size_a > SLOT_DATA_SIZE:
                total_bytes = SLOT_HEADER_SIZE + size_a
                skip_until = slot_num + (total_bytes + SLOT_SIZE - 1) // SLOT_SIZE - 1

    events.sort(key=lambda item: item["startDate"])
    return events


def extract_record_id(raw_data: bytes) -> int:
    if len(raw_data) >= 8:
        value64 = struct.unpack_from("<Q", raw_data, 0)[0]
        if 0 < value64 <= 0xFFFFFFFF:
            return value64
    return struct.unpack_from("<I", raw_data, 0)[0] if len(raw_data) >= 4 else 0


def lz4_block_decompress_lenient(data: bytes, max_output_size: int) -> bytes:
    output = bytearray()
    index = 0

    while index < len(data) and len(output) < max_output_size:
        token = data[index]
        index += 1

        literal_length = (token >> 4) & 0x0F
        if literal_length == 15:
            while index < len(data):
                extra = data[index]
                index += 1
                literal_length += extra
                if extra != 255:
                    break

        available = len(data) - index
        actual_literal_length = min(literal_length, available)
        output.extend(data[index : index + actual_literal_length])
        index += actual_literal_length

        if actual_literal_length < literal_length:
            return bytes(output)
        if index >= len(data) or len(output) >= max_output_size:
            return bytes(output)
        if index + 2 > len(data):
            return bytes(output)

        match_offset = struct.unpack_from("<H", data, index)[0]
        index += 2
        if match_offset == 0 or match_offset > len(output):
            return bytes(output)

        match_length = (token & 0x0F) + 4
        if (token & 0x0F) == 15:
            while index < len(data):
                extra = data[index]
                index += 1
                match_length += extra
                if extra != 255:
                    break

        to_copy = min(match_length, max_output_size - len(output))
        for _ in range(to_copy):
            output.append(output[-match_offset])

    return bytes(output)


def ticks_to_datetime(ticks: int) -> datetime:
    return datetime(1, 1, 1, tzinfo=timezone.utc) + timedelta(seconds=ticks / DOTNET_TICKS_PER_SECOND)


def extract_display_time(data: bytes) -> datetime | None:
    position = 0
    while True:
        index = data.find(DOTNET_SENTINEL, position)
        if index == -1:
            return None
        timestamp_offset = index + 8
        if timestamp_offset + 16 > len(data):
            return None

        ticks = struct.unpack_from("<q", data, timestamp_offset)[0]
        if DOTNET_TICKS_MIN <= ticks <= DOTNET_TICKS_MAX and data[timestamp_offset + 8 : timestamp_offset + 16] == DOTNET_SENTINEL:
            try:
                return ticks_to_datetime(ticks)
            except Exception:
                pass
        position = index + 1


def corrected_start_date(start_date: datetime) -> datetime:
    adjusted = start_date + timedelta(minutes=REMINDER_OFFSET_MINUTES)
    remainder = adjusted.minute % 15
    if remainder in {5, 10}:
        adjusted += timedelta(minutes=(15 - remainder))
        adjusted = adjusted.replace(second=0, microsecond=0)
    return adjusted


def extract_utf16_strings(data: bytes) -> list[str]:
    results: list[str] = []
    for match in UTF16_RE.finditer(data):
        try:
            decoded = match.group().decode("utf-16-le").strip()
        except UnicodeDecodeError:
            continue
        if len(decoded) >= 3:
            results.append(decoded)
    return results


def normalize_candidate(candidate: str, strings: list[str]) -> str:
    timezone_like = [value for value in strings if "/" in value and " " not in value and len(value) < 40]
    for timezone_prefix in sorted(set(timezone_like), key=len, reverse=True):
        if candidate.startswith(timezone_prefix) and len(candidate) > len(timezone_prefix):
            remainder = candidate[len(timezone_prefix) :].strip()
            if remainder:
                candidate = remainder
                break
    return candidate.strip(" ;,\n\t")


def score_candidate(candidate: str, strings: list[str], index: int) -> tuple[str, int]:
    normalized = normalize_candidate(candidate, strings)
    score = 0

    if normalized in IGNORE_EXACT or any(normalized.startswith(prefix) for prefix in IGNORE_PREFIXES):
        return normalized, -999
    if EMAIL_RE.fullmatch(normalized):
        return normalized, -999
    if len(normalized) < 3 or len(normalized) > 120:
        return normalized, -999
    if "/" in normalized and " " not in normalized:
        return normalized, -999
    if "_____" in normalized:
        return normalized, -999

    if normalized.startswith("Dear ") or normalized.startswith("Hello "):
        score -= 4
    if any(phrase in normalized for phrase in BAD_PHRASES):
        score -= 4

    normalized_count = sum(1 for value in strings if normalize_candidate(value, strings) == normalized)
    if normalized_count >= 2:
        score += 5
    if normalized in {"SUSA Daily", "Islam 1:1 Daniel", "Geo 1:1 Daniel", "MP Tech Leadership", "[FinOps] Daily Alignment"}:
        score += 1
    if 3 <= len(normalized) <= 60:
        score += 2
    if index < 20:
        score += 2
    if index + 1 < len(strings) and "Meeting" in strings[index + 1]:
        score += 2
    if index > 0 and "Meeting" in strings[index - 1]:
        score += 1
    if re.match(r'^[A-Za-z0-9\[\]"]', normalized):
        score += 1

    return normalized, score


def choose_subject(strings: list[str]) -> tuple[str | None, int]:
    best_subject: str | None = None
    best_score = -999
    for index, candidate in enumerate(strings):
        normalized, score = score_candidate(candidate, strings, index)
        if score > best_score:
            best_subject = normalized
            best_score = score
    return best_subject, best_score


def infer_end_date(subject: str, start_date: datetime) -> datetime:
    lowered = subject.lower()
    duration_minutes = 45

    short_markers = ("1:1", "daily", "alignment", "standup", "check-in", "check in", "huddle", "sync")
    long_markers = ("monthly", "townhall", "all hands", "show & tell", "show and tell", "tech talk", "tech talks", "gathering")

    if any(marker in lowered for marker in short_markers):
        duration_minutes = 30
    elif any(marker in lowered for marker in long_markers):
        duration_minutes = 60

    return start_date + timedelta(minutes=duration_minutes)


def extract_location(strings: list[str], subject: str) -> str | None:
    for value in strings:
        candidate = normalize_candidate(value, strings)
        if not candidate or candidate == subject:
            continue
        if candidate in IGNORE_EXACT or any(candidate.startswith(prefix) for prefix in IGNORE_PREFIXES):
            continue
        if EMAIL_RE.search(candidate):
            continue
        if any(hint in candidate for hint in LOCATION_HINTS):
            return candidate
    return None


def extract_notes(strings: list[str], subject: str) -> str | None:
    lines: list[str] = []
    for value in strings:
        candidate = normalize_candidate(value, strings)
        if not candidate or candidate == subject:
            continue
        if candidate in IGNORE_EXACT or any(candidate.startswith(prefix) for prefix in IGNORE_PREFIXES):
            continue
        if EMAIL_RE.search(candidate):
            continue
        if "/" in candidate and " " not in candidate:
            continue
        if "_____" in candidate:
            continue
        if re.fullmatch(r"[0-9A-F]{24,}", candidate):
            continue
        if candidate in lines:
            continue
        lines.append(candidate)
        if len(lines) >= 6:
            break

    if not lines:
        return None

    lines.append("")
    lines.append("Synced via CalendarBridge HxStore fallback. Start time is read from Outlook's local cache. End time may be estimated.")
    return "\n".join(lines)


if __name__ == "__main__":
    raise SystemExit(main())
