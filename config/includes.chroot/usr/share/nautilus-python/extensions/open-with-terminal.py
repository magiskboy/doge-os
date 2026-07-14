# Nautilus context menu: Open with Terminal (Ptyxis).
# Requires python3-nautilus. API: Nautilus 4 / nautilus-python 4.x.
from __future__ import annotations

import subprocess
from typing import List

from gi.repository import GObject, Nautilus


def _folder_path(file: Nautilus.FileInfo) -> str | None:
    if file.get_uri_scheme() != "file":
        return None
    location = file.get_location()
    return location.get_path() if location is not None else None


def _open_ptyxis(path: str) -> None:
    subprocess.Popen(
        ["ptyxis", "--new-window", f"--working-directory={path}"],
        start_new_session=True,
    )


class OpenWithTerminalExtension(GObject.GObject, Nautilus.MenuProvider):
    def _activate(self, _menu: Nautilus.MenuItem, file: Nautilus.FileInfo) -> None:
        path = _folder_path(file)
        if path:
            _open_ptyxis(path)

    def get_file_items(
        self,
        files: List[Nautilus.FileInfo],
    ) -> List[Nautilus.MenuItem]:
        if len(files) != 1:
            return []

        file = files[0]
        if not file.is_directory() or _folder_path(file) is None:
            return []

        item = Nautilus.MenuItem(
            name="LotusOS::open_with_terminal",
            label="Open with Terminal",
        )
        item.connect("activate", self._activate, file)
        return [item]

    def get_background_items(
        self,
        current_folder: Nautilus.FileInfo,
    ) -> List[Nautilus.MenuItem]:
        if _folder_path(current_folder) is None:
            return []

        item = Nautilus.MenuItem(
            name="LotusOS::open_with_terminal_bg",
            label="Open with Terminal",
        )
        item.connect("activate", self._activate, current_folder)
        return [item]
