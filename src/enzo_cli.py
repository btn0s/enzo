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
APPLE_SCRIPT = PROJECT_ROOT / "scripts" / "update_feed_reminder.applescript"


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
    return Config(
        endpoint=endpoint,
        token=token,
        timezone=str(setting("ENZO_TIMEZONE", "timezone", DEFAULT_TIMEZONE)),
        interval_minutes=int(setting("ENZO_INTERVAL_MINUTES", "interval_minutes", DEFAULT_INTERVAL_MINUTES)),
        reminder_list=str(setting("ENZO_REMINDER_LIST", "reminder_list", DEFAULT_LIST)),
        reminder_name=str(setting("ENZO_REMINDER_NAME", "reminder_name", DEFAULT_REMINDER)),
    )


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


def update_reminder(config: Config, due: datetime) -> str:
    try:
        completed = subprocess.run(
            ["osascript", *reminder_args(config, due)],
            check=True,
            capture_output=True,
            text=True,
            timeout=30,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        stderr = getattr(exc, "stderr", "") or ""
        raise EnzoError(f"Reminder update failed: {stderr.strip() or exc}") from exc
    return completed.stdout.strip()


def event_payload(
    config: Config,
    *,
    event: str,
    occurred_at: datetime,
    milk_type: str | None = None,
    amount_ml: float | None = None,
    details: str = "",
    notes: str = "",
    event_id: str | None = None,
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "action": "log",
        "token": config.token,
        "id": event_id or str(uuid.uuid4()),
        "occurred_at": occurred_at.isoformat(),
        "event": event,
        "milk_type": milk_type or "",
        "amount_ml": amount_ml,
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
    if payload["event"] != "Eating":
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

    for command, help_text in (
        ("pee", "log a wet diaper"),
        ("poop", "log a dirty diaper"),
        ("both", "log a wet and dirty diaper"),
    ):
        child = subparsers.add_parser(command, help=help_text)
        add_common_event_args(child)

    repair = subparsers.add_parser("repair-reminder", help="move reminder without writing a row")
    repair.add_argument("--at", required=True, help="feeding time")

    subparsers.add_parser("status", help="read tracker status from the endpoint")
    subparsers.add_parser("doctor", help="verify endpoint and Reminders access")

    setup = subparsers.add_parser("configure", help="save endpoint and token")
    setup.add_argument("--endpoint", required=True)
    setup.add_argument("--token", help="prefer the hidden prompt; useful for automation")
    setup.add_argument("--timezone", default=DEFAULT_TIMEZONE)
    setup.add_argument("--interval-minutes", type=int, default=DEFAULT_INTERVAL_MINUTES)
    setup.add_argument("--reminder-list", default=DEFAULT_LIST)
    setup.add_argument("--reminder-name", default=DEFAULT_REMINDER)
    return parser


def human_time(value: datetime, timezone_name: str) -> str:
    local = value.astimezone(ZoneInfo(timezone_name))
    return local.strftime("%a %b %-d at %-I:%M %p")


def run(args: argparse.Namespace) -> int:
    if args.command == "configure":
        return configure(args)

    config = load_config()
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

    event_map = {"feed": "Eating", "pee": "Pee", "poop": "Poop", "both": "Pee + Poop"}
    occurred_at = parse_time(args.at, config.timezone)
    milk_type = None
    amount_ml = None
    if args.command == "feed":
        milk_type = "Formula" if args.milk == "formula" else "Breast milk"
        amount_ml = args.amount
    payload = event_payload(
        config,
        event=event_map[args.command],
        occurred_at=occurred_at,
        milk_type=milk_type,
        amount_ml=amount_ml,
        details=args.details,
        notes=args.notes,
        event_id=args.event_id,
    )
    _, due = log_event(config, payload)
    summary = f"Logged {payload['event']} at {human_time(occurred_at, config.timezone)}"
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
