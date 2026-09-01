#!/usr/bin/env python3
"""One write path for Enzo tracker events and the next-feed reminder."""

from __future__ import annotations

import argparse
import getpass
import json
import os
import shlex
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any, Callable
from zoneinfo import ZoneInfo


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ENV_PATH = PROJECT_ROOT / ".env"
LEGACY_CONFIG_PATH = Path.home() / ".config" / "enzo" / "config.json"
DEFAULT_TIMEZONE = "America/Phoenix"
DEFAULT_INTERVAL_MINUTES = 180
DEFAULT_LIST = "Home"
DEFAULT_REMINDER = "Feed Enzo"
DEFAULT_REMINDER_ATTEMPTS = 3
DEFAULT_REMINDER_TIMEOUT_SECONDS = 30
APPLE_SCRIPT = PROJECT_ROOT / "scripts" / "update_feed_reminder.applescript"
VERIFY_SCRIPT = PROJECT_ROOT / "scripts" / "verify_feed_reminder.applescript"
URGENT_SCRIPT = PROJECT_ROOT / "scripts" / "ensure_reminder_urgent.swift"


class EnzoError(RuntimeError):
    pass


@dataclass(frozen=True)
class Config:
    endpoint: str
    token: str
    timezone: str = DEFAULT_TIMEZONE
    interval_minutes: int = DEFAULT_INTERVAL_MINUTES
    reminder_list: str = DEFAULT_LIST
    reminder_name: str = DEFAULT_REMINDER
    reminder_attempts: int = DEFAULT_REMINDER_ATTEMPTS
    reminder_timeout_seconds: int = DEFAULT_REMINDER_TIMEOUT_SECONDS


def env_path() -> Path:
    override = os.environ.get("ENZO_ENV_FILE")
    return Path(override).expanduser() if override else DEFAULT_ENV_PATH


def parse_dotenv(path: Path) -> dict[str, str]:
    """Read the small, shell-compatible subset used by this project."""
    try:
        lines = path.read_text().splitlines()
    except FileNotFoundError:
        return {}
    except OSError as exc:
        raise EnzoError(f"Could not read environment file {path}: {exc}") from exc

    values: dict[str, str] = {}
    for line_number, raw_line in enumerate(lines, start=1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[7:].lstrip()
        if "=" not in line:
            raise EnzoError(f"Invalid environment line {path}:{line_number}")
        key, raw_value = line.split("=", 1)
        key = key.strip()
        if not key or not key.replace("_", "").isalnum() or key[0].isdigit():
            raise EnzoError(f"Invalid environment key {path}:{line_number}")
        try:
            parsed = shlex.split(raw_value, comments=True, posix=True)
        except ValueError as exc:
            raise EnzoError(f"Invalid environment value {path}:{line_number}: {exc}") from exc
        values[key] = " ".join(parsed) if parsed else ""
    return values


def legacy_config() -> dict[str, Any]:
    """Keep existing private installs working while new installs use .env."""
    override = os.environ.get("ENZO_CONFIG")
    path = Path(override).expanduser() if override else LEGACY_CONFIG_PATH
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        return {}
    except (OSError, json.JSONDecodeError) as exc:
        raise EnzoError(f"Could not read legacy configuration {path}: {exc}") from exc


def load_config(*, require_endpoint: bool = True) -> Config:
    legacy = legacy_config()
    dotenv = parse_dotenv(env_path())

    def setting(environment_key: str, legacy_key: str, default: Any = "") -> Any:
        if environment_key in os.environ:
            return os.environ[environment_key]
        if environment_key in dotenv:
            return dotenv[environment_key]
        return legacy.get(legacy_key, default)

    endpoint = str(setting("ENZO_ENDPOINT", "endpoint")).strip()
    token = str(setting("ENZO_API_TOKEN", "token")).strip()
    if require_endpoint and (not endpoint or not token):
        raise EnzoError(
            f"Missing ENZO_ENDPOINT or ENZO_API_TOKEN. Copy .env.example to {env_path()} "
            "or export the variables in your shell."
        )
    config = Config(
        endpoint=endpoint,
        token=token,
        timezone=str(setting("ENZO_TIMEZONE", "timezone", DEFAULT_TIMEZONE)),
        interval_minutes=int(setting("ENZO_INTERVAL_MINUTES", "interval_minutes", DEFAULT_INTERVAL_MINUTES)),
        reminder_list=str(setting("ENZO_REMINDER_LIST", "reminder_list", DEFAULT_LIST)),
        reminder_name=str(setting("ENZO_REMINDER_NAME", "reminder_name", DEFAULT_REMINDER)),
        reminder_attempts=int(setting(
            "ENZO_REMINDER_ATTEMPTS",
            "reminder_attempts",
            DEFAULT_REMINDER_ATTEMPTS,
        )),
        reminder_timeout_seconds=int(setting(
            "ENZO_REMINDER_TIMEOUT_SECONDS",
            "reminder_timeout_seconds",
            DEFAULT_REMINDER_TIMEOUT_SECONDS,
        )),
    )
    if config.reminder_attempts < 1:
        raise EnzoError("ENZO_REMINDER_ATTEMPTS must be at least 1")
    if config.reminder_timeout_seconds < 1:
        raise EnzoError("ENZO_REMINDER_TIMEOUT_SECONDS must be at least 1")
    return config


def parse_time(value: str | None, timezone_name: str) -> datetime:
    zone = ZoneInfo(timezone_name)
    if value is None or value.strip().lower() == "now":
        return datetime.now(zone).replace(microsecond=0)

    candidate = value.strip().replace("Z", "+00:00")
    parsed: datetime | None = None
    try:
        parsed = datetime.fromisoformat(candidate)
    except ValueError:
        for pattern in ("%m/%d/%Y %I:%M %p", "%m/%d/%Y %H:%M"):
            try:
                parsed = datetime.strptime(candidate, pattern)
                break
            except ValueError:
                pass
    if parsed is None:
        raise EnzoError(
            f"Could not parse time {value!r}; use ISO format, e.g. 2026-08-30 20:43"
        )
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=zone)
    return parsed.astimezone(zone).replace(microsecond=0)


def post_json(endpoint: str, payload: dict[str, Any]) -> dict[str, Any]:
    request = urllib.request.Request(
        endpoint,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            body = response.read().decode("utf-8")
    except (urllib.error.URLError, TimeoutError) as exc:
        raise EnzoError(f"Tracker endpoint failed: {exc}") from exc
    try:
        result = json.loads(body)
    except json.JSONDecodeError as exc:
        raise EnzoError(f"Tracker endpoint returned invalid JSON: {body[:200]}") from exc
    if not result.get("ok"):
        raise EnzoError(f"Tracker endpoint rejected the request: {result.get('error', result)}")
    return result


def reminder_args(config: Config, due: datetime) -> list[str]:
    local = due.astimezone(ZoneInfo(config.timezone))
    return [
        str(APPLE_SCRIPT),
        config.reminder_list,
        config.reminder_name,
        str(local.year),
        str(local.month),
        str(local.day),
        str(local.hour),
        str(local.minute),
        str(local.second),
    ]


def update_reminder(
    config: Config,
    due: datetime,
    *,
    runner: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
    sleeper: Callable[[float], None] = time.sleep,
) -> str:
    """Move and verify the reminder, retrying the idempotent operation."""
    last_error: Exception | None = None
    last_detail = "unknown error"
    update_args = reminder_args(config, due)

    for attempt in range(1, config.reminder_attempts + 1):
        try:
            runner(
                ["osascript", *update_args],
                check=True,
                capture_output=True,
                text=True,
                timeout=config.reminder_timeout_seconds,
            )
            completed = runner(
                ["swift", str(URGENT_SCRIPT), config.reminder_name],
                check=True,
                capture_output=True,
                text=True,
                timeout=config.reminder_timeout_seconds,
            )
            runner(
                ["osascript", str(VERIFY_SCRIPT), *update_args[1:]],
                check=True,
                capture_output=True,
                text=True,
                timeout=config.reminder_timeout_seconds,
            )
            return completed.stdout.strip()
        except (OSError, subprocess.SubprocessError) as exc:
            last_error = exc
            stderr = getattr(exc, "stderr", "") or ""
            if isinstance(stderr, bytes):
                stderr = stderr.decode("utf-8", errors="replace")
            last_detail = stderr.strip() or str(exc)
            if attempt < config.reminder_attempts:
                delay = min(2 ** (attempt - 1), 4)
                print(
                    f"Reminder attempt {attempt}/{config.reminder_attempts} failed; "
                    f"retrying in {delay}s...",
                    file=sys.stderr,
                )
                sleeper(delay)

    raise EnzoError(
        f"Reminder update failed after {config.reminder_attempts} attempts: {last_detail}"
    ) from last_error


def event_payload(
    config: Config,
    *,
    event_type: str,
    occurred_at: datetime,
    milk_type: str | None = None,
    amount_ml: float | None = None,
    pee: bool = False,
    poop: bool = False,
    details: str = "",
    notes: str = "",
    event_id: str | None = None,
) -> dict[str, Any]:
    if event_type == "feed":
        sheet_event = "Eating"
    elif event_type == "diaper" and (pee or poop):
        sheet_event = "Pee + Poop" if pee and poop else "Pee" if pee else "Poop"
    else:
        raise EnzoError("event type must be feed, or a diaper containing pee, poop, or both")

    payload: dict[str, Any] = {
        "action": "log",
        "token": config.token,
        "id": event_id or str(uuid.uuid4()),
        "occurred_at": occurred_at.isoformat(),
        "type": event_type,
        "event": sheet_event,
        "milk_type": milk_type or "",
        "amount_ml": amount_ml,
        "diaper": {"pee": pee, "poop": poop} if event_type == "diaper" else None,
        "details": details,
        "notes": notes,
        "timezone": config.timezone,
    }
    return payload


def log_event(
    config: Config,
    payload: dict[str, Any],
    *,
    poster: Callable[[str, dict[str, Any]], dict[str, Any]] = post_json,
    reminder_updater: Callable[[Config, datetime], str] = update_reminder,
) -> tuple[dict[str, Any], datetime | None]:
    result = poster(config.endpoint, payload)
    if payload["type"] != "feed":
        return result, None

    occurred_at = datetime.fromisoformat(payload["occurred_at"])
    due = occurred_at + timedelta(minutes=config.interval_minutes)
    try:
        reminder_updater(config, due)
    except EnzoError as exc:
        repair_at = occurred_at.isoformat()
        raise EnzoError(
            f"Sheet write succeeded for event {payload['id']}, but {exc}. "
            f"Repair with: bin/enzo repair-reminder --at {repair_at!r}"
        ) from exc
    return result, due


def sync_event(
    config: Config,
    envelope: dict[str, Any],
    *,
    poster: Callable[[str, dict[str, Any]], dict[str, Any]] = post_json,
    reminder_updater: Callable[[Config, datetime], str] = update_reminder,
) -> dict[str, Any]:
    """Mirror one Postgres mutation into the Sheet and shared Reminder."""
    operation = envelope.get("operation")
    if operation == "delete":
        event_id = envelope.get("eventID")
        if not isinstance(event_id, str) or not event_id:
            raise EnzoError("delete sync requires eventID")
        sheet_result = poster(config.endpoint, {
            "action": "delete_event",
            "token": config.token,
            "id": event_id,
        })
    elif operation == "upsert":
        event = envelope.get("event")
        if not isinstance(event, dict):
            raise EnzoError("upsert sync requires event")
        event_id = event.get("id")
        if not isinstance(event_id, str) or not event_id:
            raise EnzoError("upsert sync requires event.id")
        event_type = event.get("type")
        occurred_at = parse_time(event.get("occurredAt"), config.timezone)
        feed = event.get("feed") if isinstance(event.get("feed"), dict) else {}
        diaper = event.get("diaper") if isinstance(event.get("diaper"), dict) else {}
        milk_type = feed.get("milkType")
        if milk_type == "formula":
            milk_type = "Formula"
        elif milk_type == "breast-milk":
            milk_type = "Breast milk"
        payload = event_payload(
            config,
            event_type=event_type,
            occurred_at=occurred_at,
            milk_type=milk_type,
            amount_ml=feed.get("amountMl"),
            pee=diaper.get("pee") is True,
            poop=diaper.get("poop") is True,
            notes=event.get("notes") if isinstance(event.get("notes"), str) else "",
            event_id=event_id,
        )
        payload["action"] = "upsert_event"
        sheet_result = poster(config.endpoint, payload)
    else:
        raise EnzoError("sync operation must be upsert or delete")

    reminder_due = None
    if envelope.get("updateReminder") is True:
        next_feed_at = envelope.get("nextFeedAt")
        if not isinstance(next_feed_at, str) or not next_feed_at:
            raise EnzoError("feed sync requires nextFeedAt")
        reminder_due = parse_time(next_feed_at, config.timezone)
        try:
            reminder_updater(config, reminder_due)
        except EnzoError as exc:
            raise EnzoError(
                f"Sheet sync succeeded, but Reminder sync failed: {exc}"
            ) from exc

    return {
        "ok": True,
        "operation": operation,
        "sheet": sheet_result,
        "reminder_due": reminder_due.isoformat() if reminder_due else None,
    }


def amount_value(value: str | None) -> float | None:
    if value is None:
        return None
    amount = float(value)
    if amount < 0:
        raise argparse.ArgumentTypeError("amount must be zero or greater")
    return amount


def configure(args: argparse.Namespace) -> int:
    path = env_path()
    token = args.token or getpass.getpass("Apps Script token: ")
    if not token:
        raise EnzoError("Token cannot be empty")
    data = [
        ("ENZO_ENDPOINT", args.endpoint),
        ("ENZO_API_TOKEN", token),
        ("ENZO_TIMEZONE", args.timezone),
        ("ENZO_INTERVAL_MINUTES", str(args.interval_minutes)),
        ("ENZO_REMINDER_LIST", args.reminder_list),
        ("ENZO_REMINDER_NAME", args.reminder_name),
        ("ENZO_REMINDER_ATTEMPTS", str(args.reminder_attempts)),
        ("ENZO_REMINDER_TIMEOUT_SECONDS", str(args.reminder_timeout_seconds)),
    ]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(f"{key}={shlex.quote(value)}\n" for key, value in data))
    path.chmod(0o600)
    print(f"Saved {path}")
    return 0


def add_common_event_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--at", help="event time; defaults to now")
    parser.add_argument("--details", default="")
    parser.add_argument("--notes", default="")
    parser.add_argument("--id", dest="event_id", help="idempotency key for a retry")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="enzo", description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    feed = subparsers.add_parser("feed", help="log a feeding and move the urgent reminder")
    add_common_event_args(feed)
    feed.add_argument("--milk", required=True, choices=("formula", "breast-milk"))
    feed.add_argument("--amount", type=amount_value, help="milliliters; omit while unknown")

    update_feed = subparsers.add_parser("update-feed", help="update the most recent feeding without adding a row")
    update_feed.add_argument("--amount", required=True, type=amount_value, help="final milliliters")
    update_feed.add_argument("--details")
    update_feed.add_argument("--notes")

    diaper = subparsers.add_parser("diaper", help="log a diaper containing pee, poop, or both")
    add_common_event_args(diaper)
    diaper.add_argument("--pee", action="store_true", help="the diaper was wet")
    diaper.add_argument("--poop", action="store_true", help="the diaper was dirty")

    repair = subparsers.add_parser("repair-reminder", help="move reminder without writing a row")
    repair.add_argument("--at", required=True, help="feeding time")

    subparsers.add_parser(
        "sync-event",
        help="internal: read an app mutation envelope from stdin",
    )

    subparsers.add_parser("status", help="read tracker status from the endpoint")
    subparsers.add_parser("doctor", help="verify endpoint and Reminders access")

    setup = subparsers.add_parser("configure", help="save endpoint and token")
    setup.add_argument("--endpoint", required=True)
    setup.add_argument("--token", help="prefer the hidden prompt; useful for automation")
    setup.add_argument("--timezone", default=DEFAULT_TIMEZONE)
    setup.add_argument("--interval-minutes", type=int, default=DEFAULT_INTERVAL_MINUTES)
    setup.add_argument("--reminder-list", default=DEFAULT_LIST)
    setup.add_argument("--reminder-name", default=DEFAULT_REMINDER)
    setup.add_argument("--reminder-attempts", type=int, default=DEFAULT_REMINDER_ATTEMPTS)
    setup.add_argument(
        "--reminder-timeout-seconds",
        type=int,
        default=DEFAULT_REMINDER_TIMEOUT_SECONDS,
    )
    return parser


def human_time(value: datetime, timezone_name: str) -> str:
    local = value.astimezone(ZoneInfo(timezone_name))
    return local.strftime("%a %b %-d at %-I:%M %p")


def run(args: argparse.Namespace) -> int:
    if args.command == "configure":
        return configure(args)

    config = load_config()
    if args.command == "sync-event":
        try:
            envelope = json.load(sys.stdin)
        except (json.JSONDecodeError, OSError) as exc:
            raise EnzoError(f"Could not read sync envelope: {exc}") from exc
        print(json.dumps(sync_event(config, envelope)))
        return 0

    if args.command == "status":
        result = post_json(config.endpoint, {"action": "status", "token": config.token})
        print(json.dumps(result.get("status", result), indent=2))
        return 0

    if args.command == "repair-reminder":
        occurred_at = parse_time(args.at, config.timezone)
        due = occurred_at + timedelta(minutes=config.interval_minutes)
        update_reminder(config, due)
        print(f"Feed Enzo: {human_time(due, config.timezone)} (Urgent)")
        return 0

    if args.command == "update-feed":
        result = post_json(config.endpoint, {
            "action": "update_feed",
            "token": config.token,
            "amount_ml": args.amount,
            "details": args.details,
            "notes": args.notes,
        })
        occurred_at = datetime.fromisoformat(result["occurred_at"])
        due = occurred_at + timedelta(minutes=config.interval_minutes)
        update_reminder(config, due)
        print(f"Updated latest feed to {args.amount:g} mL")
        print(f"Feed Enzo: {human_time(due, config.timezone)} (Urgent)")
        return 0


    if args.command == "doctor":
        result = post_json(config.endpoint, {"action": "status", "token": config.token})
        subprocess.run(
            ["osascript", "-e", f'tell application "Reminders" to return count of reminders of list "{config.reminder_list}"'],
            check=True,
            capture_output=True,
            text=True,
            timeout=10,
        )
        print(f"Tracker endpoint: OK ({result.get('status', {}).get('row_count', '?')} rows)")
        print(f"Reminders list {config.reminder_list}: OK")
        return 0

    occurred_at = parse_time(args.at, config.timezone)
    milk_type = None
    amount_ml = None
    if args.command == "feed":
        milk_type = "Formula" if args.milk == "formula" else "Breast milk"
        amount_ml = args.amount
    elif not args.pee and not args.poop:
        raise EnzoError("a diaper needs --pee, --poop, or both")
    payload = event_payload(
        config,
        event_type=args.command,
        occurred_at=occurred_at,
        milk_type=milk_type,
        amount_ml=amount_ml,
        pee=args.pee if args.command == "diaper" else False,
        poop=args.poop if args.command == "diaper" else False,
        details=args.details,
        notes=args.notes,
        event_id=args.event_id,
    )
    _, due = log_event(config, payload)
    if args.command == "diaper":
        contents = "pee + poop" if args.pee and args.poop else "pee" if args.pee else "poop"
        summary = f"Logged diaper ({contents}) at {human_time(occurred_at, config.timezone)}"
    else:
        summary = f"Logged feed at {human_time(occurred_at, config.timezone)}"
    if args.command == "feed":
        amount = "amount pending" if amount_ml is None else f"{amount_ml:g} mL"
        summary += f" — {milk_type}, {amount}"
    print(summary)
    if due:
        print(f"Feed Enzo: {human_time(due, config.timezone)} (Urgent)")
    return 0


def main(argv: list[str] | None = None) -> int:
    try:
        return run(build_parser().parse_args(argv))
    except EnzoError as exc:
        print(f"enzo: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
