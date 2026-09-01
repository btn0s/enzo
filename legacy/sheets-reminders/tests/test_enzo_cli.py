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
    sync_event,
    update_reminder,
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
            event_type="feed",
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
        payload = event_payload(
            self.config,
            event_type="diaper",
            occurred_at=occurred_at,
            pee=True,
        )
        self.assertEqual(payload["type"], "diaper")
        self.assertEqual(payload["diaper"], {"pee": True, "poop": False})
        moved = []
        log_event(
            self.config,
            payload,
            poster=lambda endpoint, posted: {"ok": True},
            reminder_updater=lambda config, due: moved.append(due),
        )
        self.assertEqual(moved, [])

    def test_diaper_command_contains_independent_observations(self):
        args = build_parser().parse_args(["diaper", "--pee", "--poop"])
        self.assertEqual(args.command, "diaper")
        self.assertTrue(args.pee)
        self.assertTrue(args.poop)

    def test_sync_event_upserts_feed_and_moves_exact_reminder_deadline(self):
        posted = []
        reminder_dates = []
        result = sync_event(
            self.config,
            {
                "operation": "upsert",
                "event": {
                    "id": "app-feed-1",
                    "occurredAt": "2026-09-01T03:00:00-07:00",
                    "type": "feed",
                    "feed": {
                        "milkType": "formula",
                        "amountMl": 30,
                        "resetsTimer": True,
                    },
                    "notes": "",
                },
                "updateReminder": True,
                "nextFeedAt": "2026-09-01T06:00:00-07:00",
            },
            poster=lambda endpoint, payload: posted.append(payload) or {"ok": True},
            reminder_updater=lambda config, due: reminder_dates.append(due) or "updated",
        )

        self.assertEqual(posted[0]["action"], "upsert_event")
        self.assertEqual(posted[0]["id"], "app-feed-1")
        self.assertEqual(posted[0]["event"], "Eating")
        self.assertEqual(posted[0]["milk_type"], "Formula")
        self.assertEqual(reminder_dates[0].isoformat(), "2026-09-01T06:00:00-07:00")
        self.assertEqual(result["operation"], "upsert")

    def test_sync_event_deletes_by_id_without_moving_reminder(self):
        posted = []
        moved = []
        sync_event(
            self.config,
            {
                "operation": "delete",
                "eventID": "app-diaper-1",
                "updateReminder": False,
                "nextFeedAt": "2026-09-01T06:00:00-07:00",
            },
            poster=lambda endpoint, payload: posted.append(payload) or {"ok": True},
            reminder_updater=lambda config, due: moved.append(due) or "updated",
        )

        self.assertEqual(posted, [{
            "action": "delete_event",
            "token": "secret",
            "id": "app-diaper-1",
        }])
        self.assertEqual(moved, [])

    def test_reminder_failure_reports_repair_without_reposting(self):
        occurred_at = datetime(2026, 8, 30, 20, 43, tzinfo=ZoneInfo("America/Phoenix"))
        payload = event_payload(
            self.config,
            event_type="feed",
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

    def test_reminder_retries_until_verified(self):
        config = Config(
            endpoint="https://example.test/exec",
            token="secret",
            reminder_attempts=3,
            reminder_timeout_seconds=7,
        )
        due = datetime(2026, 8, 30, 23, 43, tzinfo=ZoneInfo("America/Phoenix"))
        attempts = []
        delays = []
        reminder_attempts = 0

        def runner(command, **kwargs):
            nonlocal reminder_attempts
            attempts.append((command, kwargs["timeout"]))
            if command[0] == "osascript" and "update_feed_reminder" in command[1]:
                reminder_attempts += 1
            if (
                command[0] == "osascript"
                and "update_feed_reminder" in command[1]
                and reminder_attempts < 3
            ):
                raise TimeoutError("Reminders did not answer")
            return __import__("subprocess").CompletedProcess(command, 0, "updated\n", "")

        result = update_reminder(config, due, runner=runner, sleeper=delays.append)

        self.assertEqual(result, "updated")
        self.assertEqual([command[0] for command, _ in attempts], [
            "osascript", "osascript", "osascript", "swift", "osascript",
        ])
        self.assertEqual([timeout for _, timeout in attempts], [7, 7, 7, 7, 7])
        self.assertEqual(delays, [1, 2])

    def test_reminder_attempt_verifies_urgent_after_moving_date(self):
        config = Config(endpoint="https://example.test/exec", token="secret")
        due = datetime(2026, 8, 30, 23, 43, tzinfo=ZoneInfo("America/Phoenix"))
        commands = []

        def runner(command, **kwargs):
            commands.append(command)
            return __import__("subprocess").CompletedProcess(command, 0, "ok\n", "")

        update_reminder(config, due, runner=runner, sleeper=lambda _: None)

        self.assertEqual(commands[0][0], "osascript")
        self.assertEqual(commands[1][0], "swift")
        self.assertEqual(commands[1][-1], "Feed Enzo")
        self.assertEqual(commands[2][0], "osascript")
        self.assertIn("verify_feed_reminder", commands[2][1])

    def test_reminder_stops_after_retry_limit(self):
        config = Config(
            endpoint="https://example.test/exec",
            token="secret",
            reminder_attempts=2,
        )
        due = datetime(2026, 8, 30, 23, 43, tzinfo=ZoneInfo("America/Phoenix"))
        attempts = []

        def runner(command, **kwargs):
            attempts.append(command)
            raise TimeoutError("still unavailable")

        with self.assertRaisesRegex(EnzoError, "failed after 2 attempts"):
            update_reminder(config, due, runner=runner, sleeper=lambda _: None)
        self.assertEqual(len(attempts), 2)

    def test_reminder_retries_when_urgent_verification_fails(self):
        config = Config(
            endpoint="https://example.test/exec",
            token="secret",
            reminder_attempts=2,
        )
        due = datetime(2026, 8, 30, 23, 43, tzinfo=ZoneInfo("America/Phoenix"))
        commands = []
        delays = []
        swift_calls = 0

        def runner(command, **kwargs):
            nonlocal swift_calls
            commands.append(command[0])
            if command[0] == "swift":
                swift_calls += 1
                if swift_calls == 1:
                    raise TimeoutError("Urgent verification stalled")
            return __import__("subprocess").CompletedProcess(command, 0, "ok\n", "")

        update_reminder(config, due, runner=runner, sleeper=delays.append)

        self.assertEqual(commands, [
            "osascript", "swift", "osascript", "swift", "osascript",
        ])
        self.assertEqual(delays, [1])

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
                reminder_attempts=4,
                reminder_timeout_seconds=15,
            )
            with patch.dict(os.environ, {"ENZO_ENV_FILE": str(path)}, clear=False):
                configure(args)
            values = parse_dotenv(path)
            self.assertEqual(values["ENZO_ENDPOINT"], "https://example.test/exec")
            self.assertEqual(values["ENZO_REMINDER_LIST"], "Shared Home")
            self.assertEqual(values["ENZO_REMINDER_NAME"], "Feed Baby")
            self.assertEqual(values["ENZO_REMINDER_ATTEMPTS"], "4")
            self.assertEqual(values["ENZO_REMINDER_TIMEOUT_SECONDS"], "15")
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)


if __name__ == "__main__":
    unittest.main()
