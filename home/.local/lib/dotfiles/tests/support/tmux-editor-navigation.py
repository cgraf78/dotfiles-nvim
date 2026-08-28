#!/usr/bin/env python3
"""Verify editor-owned tmux navigation through real PTYs."""

from __future__ import annotations

import argparse
import os
import pathlib
import pty
import select
import shlex
import signal
import subprocess
import tempfile
import time
import unittest


def wait_until(predicate, description: str, timeout: float = 4.0) -> None:
    """Poll authoritative tmux state instead of sleeping for guessed timing."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.02)
    raise AssertionError(f"timed out waiting for {description}")


class Client:
    """One controllable terminal attachment to the isolated tmux server."""

    def __init__(self, test: EditorNavigationTest):
        self.test = test
        self.pid, self.master = pty.fork()
        if self.pid == 0:
            os.environ.clear()
            os.environ.update(test.environment)
            os.environ["TERM"] = "xterm-256color"
            os.execvp(
                "tmux",
                ["tmux", "-S", str(test.socket), "attach-session", "-t", "editor"],
            )
        self.tty = ""
        wait_until(self._find_tty, "tmux client attachment")
        self.pump_until_quiet("initial tmux render")

    def _find_tty(self) -> bool:
        listing = self.test.tmux("list-clients", "-F", "#{client_pid} #{client_tty}", check=False)
        for line in listing.stdout.splitlines():
            fields = line.split(maxsplit=1)
            if len(fields) == 2 and fields[0] == str(self.pid):
                self.tty = fields[1]
                return True
        return False

    def pump(self, duration: float) -> bytes:
        """Drain terminal output while answering Termnav's context query."""
        output = bytearray()
        deadline = time.monotonic() + duration
        while time.monotonic() < deadline:
            ready, _, _ = select.select([self.master], [], [], 0.02)
            if not ready:
                continue
            payload = os.read(self.master, 65536)
            output.extend(payload)
            if b"\x1b[?996n" in payload:
                os.write(self.master, b"\x1b[?997;1n")
        return bytes(output)

    def pump_until_quiet(self, description: str, timeout: float = 2.0) -> bytes:
        """Collect one terminal update until its output has settled."""
        output = bytearray()
        deadline = time.monotonic() + timeout
        quiet_deadline: float | None = None
        while time.monotonic() < deadline:
            ready, _, _ = select.select([self.master], [], [], 0.02)
            if ready:
                payload = os.read(self.master, 65536)
                output.extend(payload)
                quiet_deadline = time.monotonic() + 0.1
                if b"\x1b[?996n" in payload:
                    os.write(self.master, b"\x1b[?997;1n")
                continue
            if output and quiet_deadline is not None and time.monotonic() >= quiet_deadline:
                return bytes(output)
        raise AssertionError(f"timed out waiting for {description}: {bytes(output)!r}")

    def send(self, payload: bytes) -> None:
        """Write raw terminal input without asking tmux to synthesize a key."""
        os.write(self.master, payload)

    def set_focus(self, focused: bool) -> None:
        """Send a focus transition and wait for tmux to observe it."""
        os.write(self.master, b"\x1b[I" if focused else b"\x1b[O")
        expected = "focused" if focused else "unfocused"
        deadline = time.monotonic() + 2.0
        quiet_deadline: float | None = None
        while time.monotonic() < deadline:
            ready, _, _ = select.select([self.master], [], [], 0.02)
            if ready:
                payload = os.read(self.master, 65536)
                quiet_deadline = time.monotonic() + 0.1
                if b"\x1b[?996n" in payload:
                    os.write(self.master, b"\x1b[?997;1n")
            if self.test.client_is_focused(self.tty) is not focused:
                quiet_deadline = None
                continue
            if quiet_deadline is None:
                quiet_deadline = time.monotonic() + 0.1
            elif time.monotonic() >= quiet_deadline:
                return
        raise AssertionError(f"timed out waiting for {expected} client flag")

    def close(self) -> None:
        try:
            os.kill(self.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            waited, _ = os.waitpid(self.pid, os.WNOHANG)
            if waited == self.pid:
                break
            time.sleep(0.02)
        else:
            try:
                os.kill(self.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            os.waitpid(self.pid, 0)
        os.close(self.master)


class EditorNavigationTest(unittest.TestCase):
    """Check Ctrl-backslash dispatch in an isolated real tmux client."""

    config: pathlib.Path

    def setUp(self) -> None:
        short_root = pathlib.Path("/tmp")
        short_root_usable = short_root.is_dir() and os.access(short_root, os.W_OK | os.X_OK)
        temporary_parent = str(short_root) if short_root_usable else None
        self.temporary = tempfile.TemporaryDirectory(
            prefix="dot-editor-navigation-", dir=temporary_parent
        )
        self.root = pathlib.Path(self.temporary.name)
        self.socket = self.root / "tmux socket.sock"
        self.environment = os.environ.copy()
        for variable in (
            "TMUX",
            "TMUX_PANE",
            "TERMNAV_PARENT_RELAY",
            "TERMNAV_TMUX_SESSION",
        ):
            self.environment.pop(variable, None)
        self.environment["XDG_RUNTIME_DIR"] = str(self.root)
        self.tmux(
            "-f",
            str(self.config),
            "new-session",
            "-d",
            "-s",
            "editor",
            "sleep 30",
        )
        self.active = self.active_pane()
        self.inactive = self.tmux(
            "split-window", "-d", "-P", "-F", "#{pane_id}", "sleep 30"
        ).stdout.strip()
        self.clients: list[Client] = []

    def tearDown(self) -> None:
        for client in reversed(self.clients):
            client.close()
        self.tmux("kill-server", check=False)
        self.temporary.cleanup()

    def tmux(self, *arguments: str, check: bool = True) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["tmux", "-S", str(self.socket), *arguments],
            env=self.environment,
            text=True,
            capture_output=True,
            check=check,
        )

    def client_is_focused(self, tty: str) -> bool | None:
        listing = self.tmux("list-clients", "-F", "#{client_tty} #{client_flags}", check=False)
        for line in listing.stdout.splitlines():
            fields = line.split(maxsplit=1)
            if len(fields) == 2 and fields[0] == tty:
                return "focused" in fields[1].split(",")
        return None

    def active_pane(self, socket: pathlib.Path | None = None) -> str:
        """Return the active pane from this server or a nested fixture."""
        target = socket or self.socket
        completed = subprocess.run(
            ["tmux", "-S", str(target), "display-message", "-p", "#{pane_id}"],
            env=self.environment,
            text=True,
            capture_output=True,
            check=True,
        )
        return completed.stdout.strip()

    def test_ctrl_backslash_selects_the_local_previous_pane(self) -> None:
        client = Client(self)
        self.clients.append(client)
        client.set_focus(True)
        self.tmux("select-pane", "-t", self.active)
        self.tmux("select-pane", "-t", self.inactive)
        self.assertEqual(self.inactive, self.active_pane())
        client.send(b"\x1c")
        wait_until(
            lambda: self.active_pane() == self.active,
            "Ctrl-backslash pane selection",
        )

    def test_ctrl_backslash_forwards_through_a_nested_tmux(self) -> None:
        client = Client(self)
        self.clients.append(client)
        client.set_focus(True)

        inner_socket = self.root / "inner socket.sock"
        inner_environment = self.environment.copy()
        inner_environment.pop("TMUX", None)
        inner_environment.pop("TMUX_PANE", None)

        def inner(*arguments: str, check: bool = True) -> subprocess.CompletedProcess[str]:
            return subprocess.run(
                ["tmux", "-S", str(inner_socket), *arguments],
                env=inner_environment,
                text=True,
                capture_output=True,
                check=check,
            )

        try:
            inner(
                "-f",
                str(self.config),
                "new-session",
                "-d",
                "-s",
                "nested",
                "sleep 30",
            )
            inner_first = inner("display-message", "-p", "#{pane_id}").stdout.strip()
            inner_second = inner(
                "split-window", "-d", "-P", "-F", "#{pane_id}", "sleep 30"
            ).stdout.strip()
            inner("select-pane", "-t", inner_first)
            inner("select-pane", "-t", inner_second)

            command = shlex.join(
                [
                    "env",
                    "TMUX=",
                    "TERM=tmux-256color",
                    "tmux",
                    "-S",
                    str(inner_socket),
                    "attach-session",
                    "-t",
                    "nested",
                ]
            )
            self.tmux("respawn-pane", "-k", "-t", self.active, command)
            self.tmux("select-pane", "-t", self.active)
            wait_until(
                lambda: (
                    self.tmux(
                        "display-message",
                        "-p",
                        "-t",
                        self.active,
                        "#{pane_current_command}",
                    ).stdout.strip()
                    == "tmux"
                ),
                "nested tmux foreground process",
            )

            def nested_owns_mouse() -> bool:
                client.pump(0.02)
                return (
                    self.tmux(
                        "display-message",
                        "-p",
                        "-t",
                        self.active,
                        "#{mouse_any_flag}",
                    ).stdout.strip()
                    == "1"
                )

            wait_until(nested_owns_mouse, "nested tmux mouse ownership")
            client.send(b"\x1c")
            wait_until(
                lambda: self.active_pane(inner_socket) == inner_first,
                "nested Ctrl-backslash previous-pane selection",
            )
            self.assertEqual(
                self.active,
                self.active_pane(),
                "the outer tmux must forward rather than consume the nested chord",
            )
        finally:
            inner("kill-server", check=False)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True, type=pathlib.Path)
    arguments, unittest_arguments = parser.parse_known_args()
    EditorNavigationTest.config = arguments.config
    program = unittest.main(argv=[__file__, *unittest_arguments], verbosity=2, exit=False)
    return 0 if program.result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())
