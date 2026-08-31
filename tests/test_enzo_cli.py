import argparse
import os
import stat
import sys
import tempfile
import unittest
from datetime import datetime
from pathlib import Path
from unittest.mock import patch
from zoneinfo import ZoneInfo

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from enzo_cli import (
    Config,
    EnzoError,
    build_parser,
    configure,
    event_payload,
    load_config,
    log_event,
    parse_dotenv,
    parse_time,
    reminder_args,
)


class EnzoCliTests(unittest.TestCase):
    def setUp(self):
        self.config = Config(endpoint="https://example.test/exec", token="secret")

    def test_parse_time_assumes_phoenix(self):
        result = parse_time("2026-08-30 20:43", "America/Phoenix")
        self.assertEqual(result.isoformat(), "2026-08-30T20:43:00-07:00")

    def test_feed_posts_before_moving_reminder(self):
        calls = []
        occurred_at = datetime(2026, 8, 30, 20, 43, tzinfo=ZoneInfo("America/Phoenix"))
        payload = event_payload(
            self.config,
            event="Eating",
            occurred_at=occurred_at,
            milk_type="Formula",
            amount_ml=12,
            event_id="event-1",
        )

        def poster(endpoint, posted):
            calls.append(("post", posted["id"]))
            return {"ok": True}

        def reminder(config, due):
            calls.append(("reminder", due.isoformat()))
            return "updated"

        _, due = log_event(self.config, payload, poster=poster, reminder_updater=reminder)
        self.assertEqual(calls, [
            ("post", "event-1"),
            ("reminder", "2026-08-30T23:43:00-07:00"),
        ])
        self.assertEqual(due.isoformat(), "2026-08-30T23:43:00-07:00")

    def test_diaper_does_not_move_reminder(self):
        occurred_at = datetime(2026, 8, 30, 21, 0, tzinfo=ZoneInfo("America/Phoenix"))
        payload = event_payload(self.config, event="Pee", occurred_at=occurred_at)
        moved = []
        log_event(
            self.config,
            payload,
            poster=lambda endpoint, posted: {"ok": True},
            reminder_updater=lambda config, due: moved.append(due),
        )
        self.assertEqual(moved, [])

    def test_reminder_failure_reports_repair_without_reposting(self):
        occurred_at = datetime(2026, 8, 30, 20, 43, tzinfo=ZoneInfo("America/Phoenix"))
        payload = event_payload(
            self.config,
            event="Eating",
            occurred_at=occurred_at,
            milk_type="Formula",
            event_id="event-2",
        )

        def fail(config, due):
            raise EnzoError("urgent toggle failed")

        with self.assertRaisesRegex(EnzoError, "repair-reminder"):
            log_event(
                self.config,
                payload,
                poster=lambda endpoint, posted: {"ok": True},
                reminder_updater=fail,
            )

    def test_reminder_uses_local_date_components(self):
        due = datetime(2026, 8, 30, 23, 43, tzinfo=ZoneInfo("America/Phoenix"))
        args = reminder_args(self.config, due)
        self.assertEqual(args[-6:], ["2026", "8", "30", "23", "43", "0"])

    def test_update_feed_requires_final_amount(self):
        args = build_parser().parse_args(["update-feed", "--amount", "12"])
        self.assertEqual(args.amount, 12)

    def test_dotenv_supports_quotes_comments_and_export(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / ".env"
            path.write_text(
                "# comment\n"
                "export ENZO_ENDPOINT=https://example.test/exec\n"
                "ENZO_API_TOKEN='not a real secret'\n"
                "ENZO_REMINDER_NAME=\"Feed Enzo\" # trailing comment\n"
            )
            self.assertEqual(parse_dotenv(path), {
                "ENZO_ENDPOINT": "https://example.test/exec",
                "ENZO_API_TOKEN": "not a real secret",
                "ENZO_REMINDER_NAME": "Feed Enzo",
            })

    def test_environment_overrides_dotenv(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / ".env"
            path.write_text(
                "ENZO_ENDPOINT=https://dotenv.test/exec\n"
                "ENZO_API_TOKEN=dotenv-token\n"
                "ENZO_INTERVAL_MINUTES=180\n"
            )
            environment = {
                "ENZO_ENV_FILE": str(path),
                "ENZO_ENDPOINT": "https://environment.test/exec",
                "ENZO_API_TOKEN": "environment-token",
                "ENZO_INTERVAL_MINUTES": "120",
            }
            with patch.dict(os.environ, environment, clear=False):
                config = load_config()
            self.assertEqual(config.endpoint, "https://environment.test/exec")
            self.assertEqual(config.token, "environment-token")
            self.assertEqual(config.interval_minutes, 120)

    def test_configure_writes_private_dotenv(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / ".env"
            args = argparse.Namespace(
                endpoint="https://example.test/exec",
                token="not-a-real-secret",
                timezone="America/Phoenix",
                interval_minutes=180,
                reminder_list="Shared Home",
                reminder_name="Feed Baby",
            )
            with patch.dict(os.environ, {"ENZO_ENV_FILE": str(path)}, clear=False):
                configure(args)
            values = parse_dotenv(path)
            self.assertEqual(values["ENZO_ENDPOINT"], "https://example.test/exec")
            self.assertEqual(values["ENZO_REMINDER_LIST"], "Shared Home")
            self.assertEqual(values["ENZO_REMINDER_NAME"], "Feed Baby")
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)


if __name__ == "__main__":
    unittest.main()
