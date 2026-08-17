import json
import os
from datetime import datetime


def _history_file(data_dir):
    return os.path.join(data_dir, "history.json")


def load_history(data_dir):
    path = _history_file(data_dir)
    if not os.path.isfile(path):
        return []
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def save_history(data_dir, entries):
    path = _history_file(data_dir)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(entries, f, indent=2, ensure_ascii=False)


def add_entry(data_dir, *, zip_filename, comment, ersteller, hash_, typ, status):
    entries = load_history(data_dir)
    entry = {
        "timestamp": datetime.now().isoformat(timespec="seconds"),
        "typ": typ,
        "zip_filename": zip_filename,
        "comment": comment or "",
        "ersteller": ersteller,
        "hash": hash_,
        "status": status,
    }
    entries.append(entry)
    save_history(data_dir, entries)
    return entry
