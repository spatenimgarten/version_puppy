@echo off
REM Baut version_puppy.exe mit PyInstaller (Standardbibliothek genuegt, keine
REM externen Python-Abhaengigkeiten fuer version_puppy selbst).
pip install pyinstaller
pyinstaller --onefile --name version_puppy version_puppy\__main__.py
echo.
echo Fertig. Exe liegt in dist\version_puppy.exe
pause
