$zipPath = 'C:\Program Files\YASB\lib\library.zip'
$backup = "$zipPath.bak"
$entry = 'core/widgets/yasb/clock.pyc'

if (-not (Test-Path $backup)) {
    Copy-Item $zipPath $backup
}

$py = @'
import zipfile, shutil, os, sys
from pathlib import Path

zip_path = Path(r"C:\Program Files\YASB\lib\library.zip")
entry = "core/widgets/yasb/clock.pyc"
old = b"\xda\x10NoVerticalHeader"
new = b"\xda\x0eISOWeekNumbers"
temp = Path(os.environ["TEMP"]) / "yasb-library-patched.zip"

with zipfile.ZipFile(zip_path, "r") as zin:
    data = bytearray(zin.read(entry))
    if old not in data:
        sys.exit("pattern not found")
    data = data.replace(old, new)
    with zipfile.ZipFile(temp, "w", compression=zipfile.ZIP_DEFLATED) as zout:
        for item in zin.infolist():
            payload = bytes(data) if item.filename == entry else zin.read(item.filename)
            zout.writestr(item, payload)

shutil.copy2(temp, zip_path)
print("patched")
'@

$script = Join-Path $env:TEMP 'patch-yasb-cal.py'
Set-Content -Path $script -Value $py -Encoding UTF8
python $script
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host 'YASB calendar patched: ISO week numbers in grid'
