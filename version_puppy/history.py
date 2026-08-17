import json
import os
from datetime import datetime


def history_path(data_dir, project):
    return os.path.join(data_dir, "history", f"{project}.json")


def load_history(data_dir, project):
    path = history_path(data_dir, project)
    if not os.path.isfile(path):
        return []
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def save_history(data_dir, project, entries):
    path = history_path(data_dir, project)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(entries, f, indent=2, ensure_ascii=False)


def add_entry(data_dir, project, zip_filename, comment, status):
    entries = load_history(data_dir, project)
    version = len(entries) + 1
    entry = {
        "version": version,
        "timestamp": datetime.now().isoformat(timespec="seconds"),
        "comment": comment or "",
        "zip_filename": zip_filename,
        "status": status,
    }
    entries.append(entry)
    save_history(data_dir, project, entries)
    return entry


def update_status(data_dir, project, zip_filename, status):
    entries = load_history(data_dir, project)
    for entry in entries:
        if entry["zip_filename"] == zip_filename:
            entry["status"] = status
    save_history(data_dir, project, entries)
