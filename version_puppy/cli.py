import argparse
import glob
import os
import sys
from datetime import datetime

from .archiver import zip_directory
from .config import ConfigError, get_project, load_config
from .history import add_entry, load_history, update_status
from .server_sync import copy_to_server, push_history_copy, server_reachable

DATA_DIR = "data"
PENDING_DIR = os.path.join(DATA_DIR, "pending")


def _project_pending_dir(project):
    path = os.path.join(PENDING_DIR, project)
    os.makedirs(path, exist_ok=True)
    return path


def _timestamp():
    return datetime.now().strftime("%Y%m%d_%H%M%S")


def cmd_create(args):
    projects = load_config(args.config)
    project_cfg = get_project(projects, args.project)
    source_dir = project_cfg["source_dir"]
    server_dir = project_cfg["server_dir"]

    entries = load_history(DATA_DIR, args.project)
    version = len(entries) + 1
    zip_filename = f"{args.project}_v{version}_{_timestamp()}.zip"

    pending_dir = _project_pending_dir(args.project)
    local_zip_path = os.path.join(pending_dir, zip_filename)

    print(f"Zippe '{source_dir}' -> {zip_filename} ...")
    zip_directory(source_dir, local_zip_path)

    status = "pending"
    if server_reachable(server_dir):
        try:
            copy_to_server(local_zip_path, server_dir)
            os.remove(local_zip_path)
            status = "synced"
        except OSError as exc:
            print(f"Warnung: Kopieren auf Server fehlgeschlagen ({exc}). Bleibt lokal in der Warteschlange.")
    else:
        print(f"Server '{server_dir}' nicht erreichbar. Archiv bleibt lokal in der Warteschlange: {local_zip_path}")

    add_entry(DATA_DIR, args.project, zip_filename, args.comment, status)

    if status == "synced":
        push_history_copy(DATA_DIR, args.project, server_dir)
        print(f"Version {version} erstellt und auf Server synchronisiert.")
    else:
        print(f"Version {version} erstellt, wartet auf Server-Sync.")


def cmd_sync(args):
    projects = load_config(args.config)
    any_pending = False

    for project, project_cfg in projects.items():
        pending_dir = _project_pending_dir(project)
        pending_files = sorted(glob.glob(os.path.join(pending_dir, "*.zip")))
        if not pending_files:
            continue

        server_dir = project_cfg["server_dir"]
        if not server_reachable(server_dir):
            print(f"[{project}] Server weiterhin nicht erreichbar ({len(pending_files)} ausstehend).")
            any_pending = True
            continue

        for local_zip_path in pending_files:
            zip_filename = os.path.basename(local_zip_path)
            try:
                copy_to_server(local_zip_path, server_dir)
                os.remove(local_zip_path)
                update_status(DATA_DIR, project, zip_filename, "synced")
                print(f"[{project}] Nachträglich synchronisiert: {zip_filename}")
            except OSError as exc:
                print(f"[{project}] Fehler beim Nachsynchronisieren von {zip_filename}: {exc}")
                any_pending = True

        push_history_copy(DATA_DIR, project, server_dir)

    if not any_pending:
        print("Alles synchronisiert.")


def cmd_history(args):
    entries = load_history(DATA_DIR, args.project)
    if not entries:
        print(f"Keine Historie für Projekt '{args.project}'.")
        return
    for e in entries:
        comment = f" – {e['comment']}" if e["comment"] else ""
        print(f"v{e['version']:<4} {e['timestamp']}  [{e['status']:<7}]  {e['zip_filename']}{comment}")


def build_parser():
    parser = argparse.ArgumentParser(
        prog="version_puppy",
        description="Automatisierte Versionierung für TIA Portal / SIMATIC Manager Projekte",
    )
    parser.add_argument("--config", default="config.json", help="Pfad zur config.json (Standard: config.json)")
    sub = parser.add_subparsers(dest="command", required=True)

    p_create = sub.add_parser("create", help="Neue Version erstellen (zippen + auf Server kopieren)")
    p_create.add_argument("project", help="Projektname aus der Konfiguration")
    p_create.add_argument("--comment", default="", help="Optionale Notiz zu dieser Version")
    p_create.set_defaults(func=cmd_create)

    p_sync = sub.add_parser("sync", help="Ausstehende Kopien auf den Server nachholen")
    p_sync.set_defaults(func=cmd_sync)

    p_history = sub.add_parser("history", help="Historie eines Projekts anzeigen")
    p_history.add_argument("project", help="Projektname aus der Konfiguration")
    p_history.set_defaults(func=cmd_history)

    return parser


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        args.func(args)
    except ConfigError as exc:
        print(f"Konfigurationsfehler: {exc}", file=sys.stderr)
        sys.exit(1)
    except (NotADirectoryError, OSError) as exc:
        print(f"Fehler: {exc}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
