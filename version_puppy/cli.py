import argparse
import os
import sys
from datetime import datetime

from .archiver import zip_directory
from .hashing import sha256_of_file
from .history import add_entry
from .naming import NamingError, next_version_dir_name, parse_version_name


def cmd_version(args):
    source_dir = os.path.abspath(args.source_dir)
    if not os.path.isdir(source_dir):
        raise NotADirectoryError(f"Quellverzeichnis nicht gefunden: {source_dir}")

    current_name = os.path.basename(source_dir.rstrip(os.sep))
    parse_version_name(current_name)

    pending_dir = os.path.join(args.data_dir, "pending")
    os.makedirs(pending_dir, exist_ok=True)

    if args.typ == "version":
        zip_filename = f"{current_name}.zip"
    else:
        timestamp = datetime.now().strftime("%Y-%m-%d_%H%M%S")
        zip_filename = f"{current_name}_{args.user}_{timestamp}.zip"

    zip_path = os.path.join(pending_dir, zip_filename)

    print(f"Zippe '{source_dir}' -> {zip_filename} ...")
    zip_directory(source_dir, zip_path)

    print("Berechne Prüfsumme ...")
    file_hash = sha256_of_file(zip_path)

    add_entry(
        args.data_dir,
        zip_filename=zip_filename,
        comment=args.comment,
        ersteller=args.user,
        hash_=file_hash,
        typ=args.typ,
        status="pending",
    )
    print(f"Archiv erstellt: {zip_path}")
    print(f"Hash: {file_hash}")

    if args.typ == "version":
        new_name = next_version_dir_name(current_name)
        new_path = os.path.join(os.path.dirname(source_dir), new_name)
        try:
            os.rename(source_dir, new_path)
            print(f"Projektverzeichnis umbenannt: {current_name} -> {new_name}")
        except OSError as exc:
            print(
                f"WARNUNG: Version wurde erstellt, aber Umbenennen von "
                f"'{current_name}' zu '{new_name}' ist fehlgeschlagen ({exc}). "
                f"Bitte manuell umbenennen.",
                file=sys.stderr,
            )


def build_parser():
    parser = argparse.ArgumentParser(
        prog="version_puppy",
        description="Automatisierte Versionierung für TIA Portal / SIMATIC Manager Projekte",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    p_version = sub.add_parser("version", help="Version oder Zwischenversion erstellen (rein lokal)")
    p_version.add_argument("--source-dir", required=True, help="Pfad zum Projektverzeichnis (z.B. ...\\123456_TIA19_V001)")
    p_version.add_argument("--data-dir", required=True, help="Pfad zum lokalen Datenverzeichnis (Historie + Warteschlange)")
    p_version.add_argument("--user", required=True, help="Benutzerkürzel (z.B. AF)")
    p_version.add_argument("--comment", default="", help="Optionaler Kommentar")
    p_version.add_argument("--typ", choices=["version", "zwischenversion"], required=True)
    p_version.set_defaults(func=cmd_version)

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
