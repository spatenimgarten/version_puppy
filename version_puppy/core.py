import os
from datetime import datetime

from .archiver import zip_directory
from .hashing import sha256_of_file
from .history import add_entry
from .naming import next_version_dir_name, parse_version_name


class VersionResult:
    def __init__(self, zip_path, file_hash, renamed_to=None, rename_error=None):
        self.zip_path = zip_path
        self.file_hash = file_hash
        self.renamed_to = renamed_to
        self.rename_error = rename_error


def create_version(source_dir, data_dir, user, typ, comment):
    source_dir = os.path.abspath(source_dir)
    if not os.path.isdir(source_dir):
        raise NotADirectoryError(f"Quellverzeichnis nicht gefunden: {source_dir}")

    current_name = os.path.basename(source_dir.rstrip(os.sep))
    parse_version_name(current_name)

    pending_dir = os.path.join(data_dir, "pending")
    os.makedirs(pending_dir, exist_ok=True)

    if typ == "version":
        zip_filename = f"{current_name}.zip"
    else:
        timestamp = datetime.now().strftime("%Y-%m-%d_%H%M%S")
        zip_filename = f"{current_name}_{user}_{timestamp}.zip"

    zip_path = os.path.join(pending_dir, zip_filename)
    zip_directory(source_dir, zip_path)
    file_hash = sha256_of_file(zip_path)

    add_entry(
        data_dir,
        zip_filename=zip_filename,
        comment=comment,
        ersteller=user,
        hash_=file_hash,
        typ=typ,
        status="pending",
    )

    renamed_to = None
    rename_error = None
    if typ == "version":
        new_name = next_version_dir_name(current_name)
        new_path = os.path.join(os.path.dirname(source_dir), new_name)
        try:
            os.rename(source_dir, new_path)
            renamed_to = new_name
        except OSError as exc:
            rename_error = str(exc)

    return VersionResult(zip_path, file_hash, renamed_to, rename_error)
