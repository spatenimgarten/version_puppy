import argparse
import sys

from .core import create_version
from .naming import NamingError
from .server_sync import server_reachable
from .sync import run_sync


def cmd_version(args):
    result = create_version(args.source_dir, args.data_dir, args.user, args.typ, args.comment)
    print(f"Archiv erstellt: {result.zip_path}")
    print(f"Hash: {result.file_hash}")
    if result.renamed_to:
        print(f"Projektverzeichnis umbenannt: -> {result.renamed_to}")
    if result.rename_error:
        print(
            f"WARNUNG: Version wurde erstellt, aber Umbenennen ist fehlgeschlagen "
            f"({result.rename_error}). Bitte manuell umbenennen.",
            file=sys.stderr,
        )


def cmd_sync(args):
    if not server_reachable(args.server_dir):
        print(f"Server '{args.server_dir}' nicht erreichbar.")
        return
    summary = run_sync(args.data_dir, args.server_dir)
    print(f"Synchronisiert: {len(summary.synced)}")
    if summary.conflicts:
        print(f"Konflikte ({len(summary.conflicts)}): " + ", ".join(summary.conflicts))
    if summary.pruned:
        print(f"Aufgeräumt: {len(summary.pruned)}")


def cmd_gui(args):
    from .gui import run_gui

    run_gui(args.source_dir, args.data_dir, args.user, args.server_dir)


def build_parser():
    parser = argparse.ArgumentParser(
        prog="version_puppy",
        description="Automatisierte Versionierung für TIA Portal / SIMATIC Manager Projekte",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    p_version = sub.add_parser("version", help="Version oder Zwischenversion erstellen (rein lokal, ohne Oberfläche)")
    p_version.add_argument("--source-dir", required=True, help="Pfad zum Projektverzeichnis (z.B. ...\\123456_TIA19_V001)")
    p_version.add_argument("--data-dir", required=True, help="Pfad zum lokalen Datenverzeichnis (Historie + Warteschlange)")
    p_version.add_argument("--user", required=True, help="Benutzerkürzel (z.B. AF)")
    p_version.add_argument("--comment", default="", help="Optionaler Kommentar")
    p_version.add_argument("--typ", choices=["version", "zwischenversion"], required=True)
    p_version.set_defaults(func=cmd_version)

    p_sync = sub.add_parser("sync", help="Ausstehende Versionen mit dem Server abgleichen (ohne Oberfläche, z.B. für Hintergrund-Aufruf)")
    p_sync.add_argument("--data-dir", required=True, help="Pfad zum lokalen Datenverzeichnis (Historie + Warteschlange)")
    p_sync.add_argument("--server-dir", required=True, help="Pfad zum Serververzeichnis")
    p_sync.set_defaults(func=cmd_sync)

    p_gui = sub.add_parser("gui", help="Oberfläche mit drei Knöpfen öffnen (Version / Zwischenversion / Beenden)")
    p_gui.add_argument("--source-dir", required=True, help="Pfad zum Projektverzeichnis (z.B. ...\\123456_TIA19_V001)")
    p_gui.add_argument("--data-dir", required=True, help="Pfad zum lokalen Datenverzeichnis (Historie + Warteschlange)")
    p_gui.add_argument("--user", required=True, help="Benutzerkürzel (z.B. AF)")
    p_gui.add_argument("--server-dir", required=True, help="Pfad zum Serververzeichnis")
    p_gui.set_defaults(func=cmd_gui)

    return parser


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        args.func(args)
    except NamingError as exc:
        print(f"Fehler: {exc}", file=sys.stderr)
        sys.exit(1)
    except (NotADirectoryError, OSError) as exc:
        print(f"Fehler: {exc}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
