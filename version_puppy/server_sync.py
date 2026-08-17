import json
import os
import threading


def server_reachable(server_dir, timeout=3.0):
    result = {"reachable": False}

    def _check():
        result["reachable"] = os.path.isdir(server_dir)

    thread = threading.Thread(target=_check, daemon=True)
    thread.start()
    thread.join(timeout)
    return result["reachable"]


def _history_path(server_dir):
    return os.path.join(server_dir, "history.json")


def _html_path(server_dir):
    return os.path.join(server_dir, "history.html")


def load_server_history(server_dir):
    path = _history_path(server_dir)
    if not os.path.isfile(path):
        return []
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def save_server_history(server_dir, entries):
    os.makedirs(server_dir, exist_ok=True)
    with open(_history_path(server_dir), "w", encoding="utf-8") as f:
        json.dump(entries, f, indent=2, ensure_ascii=False)
    _write_html(server_dir, entries)


def _write_html(server_dir, entries):
    rows = "\n".join(
        "<tr><td>{typ}</td><td>{timestamp}</td><td>{ersteller}</td>"
        "<td>{zip_filename}</td><td>{comment}</td><td><code>{hash_short}</code></td></tr>".format(
            typ=e["typ"],
            timestamp=e["timestamp"],
            ersteller=e["ersteller"],
            zip_filename=e["zip_filename"],
            comment=e.get("comment", ""),
            hash_short=e["hash"][:12],
        )
        for e in sorted(entries, key=lambda x: x["timestamp"], reverse=True)
    )
    html = f"""<!doctype html>
<html><head><meta charset="utf-8"><title>Versionshistorie</title>
<style>
body {{ font-family: sans-serif; margin: 2rem; }}
table {{ border-collapse: collapse; width: 100%; }}
th, td {{ border: 1px solid #ccc; padding: 6px 10px; text-align: left; font-size: 0.9rem; }}
th {{ background: #f0f0f0; }}
</style></head>
<body>
<h1>Versionshistorie</h1>
<table>
<tr><th>Typ</th><th>Zeitstempel</th><th>Ersteller</th><th>Dateiname</th><th>Kommentar</th><th>Hash</th></tr>
{rows}
</table>
</body></html>
"""
    with open(_html_path(server_dir), "w", encoding="utf-8") as f:
        f.write(html)
