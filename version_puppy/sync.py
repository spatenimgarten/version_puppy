import os
import shutil

from .history import load_history, save_history
from .server_sync import load_server_history, save_server_history


class SyncSummary:
    def __init__(self):
        self.synced = []
        self.conflicts = []
        self.pruned = []


def _prune_superseded_zwischenversionen(entry, local_entries, server_entries, server_by_name, data_dir, server_dir, summary):
    pending_dir = os.path.join(data_dir, "pending")
    base_name = entry["zip_filename"][: -len(".zip")]
    prefix = base_name + "_"
    removed_names = set()

    for other in local_entries:
        if other is entry or other["typ"] != "zwischenversion":
            continue
        if not other["zip_filename"].startswith(prefix):
            continue

        other_zip = other["zip_filename"]
        local_path = os.path.join(pending_dir, other_zip)
        if os.path.isfile(local_path):
            os.remove(local_path)

        server_path = os.path.join(server_dir, other_zip)
        if os.path.isfile(server_path):
            os.remove(server_path)

        if other_zip in server_by_name:
            try:
                server_entries.remove(server_by_name[other_zip])
            except ValueError:
                pass
            del server_by_name[other_zip]

        removed_names.add(other_zip)
        summary.pruned.append(other_zip)

    return removed_names


def run_sync(data_dir, server_dir):
    summary = SyncSummary()
    local_entries = load_history(data_dir)
    server_entries = load_server_history(server_dir)
    server_by_name = {e["zip_filename"]: e for e in server_entries}
    pending_dir = os.path.join(data_dir, "pending")

    to_remove = set()

    for entry in local_entries:
        if entry["status"] != "pending":
            continue

        zip_filename = entry["zip_filename"]
        local_zip_path = os.path.join(pending_dir, zip_filename)
        existing = server_by_name.get(zip_filename)

        if existing is not None:
            if existing["hash"] == entry["hash"]:
                entry["status"] = "synced"
                if os.path.isfile(local_zip_path):
                    os.remove(local_zip_path)
                summary.synced.append(zip_filename)
            else:
                entry["status"] = "conflict"
                summary.conflicts.append(zip_filename)
            continue

        if not os.path.isfile(local_zip_path):
            continue

        os.makedirs(server_dir, exist_ok=True)
        shutil.copy2(local_zip_path, os.path.join(server_dir, zip_filename))
        server_copy = {k: v for k, v in entry.items() if k != "status"}
        server_entries.append(server_copy)
        server_by_name[zip_filename] = server_copy
        os.remove(local_zip_path)
        entry["status"] = "synced"
        summary.synced.append(zip_filename)

        if entry["typ"] == "version":
            to_remove |= _prune_superseded_zwischenversionen(
                entry, local_entries, server_entries, server_by_name, data_dir, server_dir, summary
            )

    if to_remove:
        local_entries = [e for e in local_entries if e["zip_filename"] not in to_remove]

    save_history(data_dir, local_entries)
    save_server_history(server_dir, server_entries)
    return summary
