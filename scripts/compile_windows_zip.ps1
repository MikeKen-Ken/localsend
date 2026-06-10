# UNCOMMENT THESE LINES TO BUILD FROM LATEST COMMIT
# git reset --hard origin/main
# git pull

.\scripts\compile_windows_msix_helper.ps1

cd app

fvm flutter clean
fvm flutter pub get
fvm flutter build windows

Compress-Archive -Path build/windows/x64/runner/Release/* -DestinationPath LocalSend-XXX-windows-x86-64.zip

cd ..

Write-Output 'Generated Windows zip!'