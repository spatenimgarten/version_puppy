import os
import shutil
import threading

from .history import history_path


def server_reachable(server_dir, timeout=3.0):
    result = {"reachable": False}

    def _check():
        result["reachable"] = os.path.isdir(server_dir)

    thread = threading.Thread(target=_check, daemon=True)
    thread.start()
    thread.join(timeout)
    return result["reachable"]


def copy_to_server(local_zip_path, server_dir):
    os.makedirs(server_dir, exist_ok=True)
    dest = os.path.join(server_dir, os.path.basename(local_zip_path))
    shutil.copy2(local_zip_path, dest)
    return dest


def push_history_copy(data_dir, project, server_dir):
    src = history_path(data_dir, project)
    if not os.path.isfile(src):
        return
    dest = os.path.join(server_dir, f"_history_{project}.json")
    shutil.copy2(src, dest)
