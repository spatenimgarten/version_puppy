import os
import tkinter as tk
from tkinter import filedialog, messagebox

from .batch_template import render_batch
from .naming import NamingError, split_project_dir
from .settings import load_setup_defaults, save_setup_defaults


def run_setup_gui():
    defaults = load_setup_defaults()

    root = tk.Tk()
    root.title("version_puppy – Neues Projekt einrichten")
    root.resizable(False, False)

    tk.Label(root, text="Projekt einrichten", font=("Segoe UI", 11, "bold")).grid(
        row=0, column=0, columnspan=3, padx=16, pady=(16, 8), sticky="w"
    )

    def add_row(row, label_text, browse=False, default=""):
        tk.Label(root, text=label_text).grid(row=row, column=0, padx=(16, 4), pady=4, sticky="w")
        var = tk.StringVar(value=default)
        entry = tk.Entry(root, textvariable=var, width=45)
        entry.grid(row=row, column=1, padx=4, pady=4)
        if browse:
            def do_browse():
                path = filedialog.askdirectory(parent=root)
                if path:
                    var.set(path)

            tk.Button(root, text="Durchsuchen...", takefocus=0, command=do_browse).grid(
                row=row, column=2, padx=(4, 16), pady=4
            )
        return var

    # Projektverzeichnis ist immer projektspezifisch und bleibt daher leer,
    # die uebrigen Felder aendern sich selten zwischen Projekten und werden
    # deshalb aus der letzten Eingabe vorbelegt.
    projekt_var = add_row(1, "Projektverzeichnis (schon angelegt, endet auf _V001):", browse=True)
    server_var = add_row(2, "Serververzeichnis:", browse=True, default=defaults.get("server_dir", ""))
    kuerzel_var = add_row(3, "Benutzerkürzel:", default=defaults.get("kuerzel", ""))
    software_var = add_row(
        4, "Startkommando Programmiersoftware (optional):", default=defaults.get("software_kommando", "")
    )

    def erstellen():
        projekt_dir = projekt_var.get().strip()
        server_dir = server_var.get().strip()
        kuerzel = kuerzel_var.get().strip()
        software_kommando = software_var.get().strip()

        if not projekt_dir or not os.path.isdir(projekt_dir):
            messagebox.showerror("Fehler", "Projektverzeichnis existiert nicht.", parent=root)
            return
        if not server_dir:
            messagebox.showerror("Fehler", "Bitte Serververzeichnis angeben.", parent=root)
            return
        if not kuerzel:
            messagebox.showerror("Fehler", "Bitte Benutzerkürzel angeben.", parent=root)
            return

        try:
            prefix, basis = split_project_dir(projekt_dir)
        except NamingError as exc:
            messagebox.showerror("Fehler", str(exc), parent=root)
            return

        batch_content = render_batch(prefix, basis, server_dir, kuerzel, software_kommando)
        batch_path = os.path.join(basis, f"start_{prefix}.bat")

        if os.path.exists(batch_path):
            if not messagebox.askyesno(
                "Überschreiben?", f"'{batch_path}' existiert bereits. Überschreiben?", parent=root
            ):
                return

        with open(batch_path, "w", encoding="utf-8") as f:
            f.write(batch_content)

        save_setup_defaults(kuerzel=kuerzel, server_dir=server_dir, software_kommando=software_kommando)

        messagebox.showinfo("Fertig", f"Batchdatei erstellt:\n{batch_path}", parent=root)
        root.destroy()

    tk.Button(
        root, text="Batchdatei erstellen", width=28, height=2, takefocus=0, command=erstellen
    ).grid(row=5, column=0, columnspan=3, pady=16)

    root.bind("<Return>", lambda e: "break")

    root.mainloop()
