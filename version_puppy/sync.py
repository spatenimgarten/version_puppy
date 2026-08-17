import os
import shutil
from datetime import datetime

from .history import load_history, save_history
from .server_sync import load_server_history, save_server_history


class SyncSummary:
    def __init__(self):
        self.synced = []
        self.conflicts = []  # Liste von (neuer_dateiname, kollidierender_bestehender_dateiname)
        self.pruned = []


def _conflict_filename(original_zip_filename, entry):
    base = original_zip_filename[: -len(".zip")]
    timestamp = datetime.now().strftime("%Y-%m-%d_%H%M%S")
    return f"{base}_KONFLIKT_{entry['ersteller']}_{timestamp}.zip"


def _prune_superseded_zwischenversionen(
    base_zip_filename, entry, local_entries, server_entries, server_by_name, data_dir, server_dir, summary
):
    pending_dir = os.path.join(data_dir, "pending")
    base_name = base_zip_filename[: -len(".zip")]
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

        original_zip_filename = entry["zip_filename"]
        local_zip_path = os.path.join(pending_dir, original_zip_filename)
        existing = server_by_name.get(original_zip_filename)

        if existing is not None and existing["hash"] == entry["hash"]:
            entry["status"] = "synced"
            if os.path.isfile(local_zip_path):
                os.remove(local_zip_path)
            summary.synced.append(original_zip_filename)
            continue

        if not os.path.isfile(local_zip_path):
            continue

        os.makedirs(server_dir, exist_ok=True)

        is_conflict = existing is not None
        if is_conflict:
            # Gleicher Zielname, anderer Inhalt: trotzdem kopieren, aber unter
            # eindeutigem Namen - nichts geht verloren, aber die bestehende
            # Datei wird nicht stillschweigend ueberschrieben.
            target_name = _conflict_filename(original_zip_filename, entry)
            entry["status"] = "conflict"
            entry["conflict_with"] = original_zip_filename
            summary.conflicts.append((target_name, original_zip_filename))
        else:
            target_name = original_zip_filename
            entry["status"] = "synced"
            summary.synced.append(target_name)

        entry["zip_filename"] = target_name

        shutil.copy2(local_zip_path, os.path.join(server_dir, target_name))
        server_copy = {k: v for k, v in entry.items() if k != "status"}
        if is_conflict:
            server_copy["status"] = "conflict"
            server_copy["conflict_with"] = original_zip_filename
        server_entries.append(server_copy)
        server_by_name[target_name] = server_copy

        if is_conflict:
            # Lokale Kopie NICHT loeschen, sondern auf denselben Namen wie auf
            # dem Server umbenennen - bleibt griffbereit fuer die manuelle
            # Klaerung statt nur noch auf dem Server zu liegen.
            os.rename(local_zip_path, os.path.join(pending_dir, target_name))
        else:
            os.remove(local_zip_path)

        if entry["typ"] == "version":
            to_remove |= _prune_superseded_zwischenversionen(
                original_zip_filename,
                entry,
                local_entries,
                server_entries,
                server_by_name,
                data_dir,
                server_dir,
                summary,
            )

    if to_remove:
        local_entries = [e for e in local_entries if e["zip_filename"] not in to_remove]

    save_history(data_dir, local_entries)
    save_server_history(server_dir, server_entries)
    return summary
