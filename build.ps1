# Build DeepTestGuard. Requires JDK 17 (javac/keytool), Android build-tools 34, android.jar (platform-34).
# Tool paths below point at local copies; override with -Bt / -Jar if they were cleaned up.
# NOTE: keep this file ASCII-only, Windows PowerShell 5.1 mangles non-ASCII scripts.
param(
  [string]$Bt  = 'C:\Users\ZYTEric\AppData\Local\Temp\bt34\android-14',
  [string]$Jar = 'C:\Users\ZYTEric\AppData\Local\Temp\plat34\android-34\android.jar'
)
$ErrorActionPreference = 'Stop'
$bt  = $Bt
$jar = $Jar
Set-Location $PSScriptRoot

# clean
foreach ($d in 'build\classes','build\dex') {
  if (Test-Path $d) { Remove-Item -Recurse -Force $d }
}
New-Item -ItemType Directory -Force -Path 'build\classes','build\dex' | Out-Null

Write-Host '== javac =='
$srcs = Get-ChildItem -Recurse -Filter *.java src | ForEach-Object { $_.FullName }
& javac -encoding UTF-8 -source 8 -target 8 -nowarn -bootclasspath $jar -d build\classes @srcs
if ($LASTEXITCODE -ne 0) { throw "javac failed: $LASTEXITCODE" }

Write-Host '== d8 =='
$cls = Get-ChildItem -Recurse -Filter *.class 'build\classes\com\dualos\deeptestguard' | ForEach-Object { $_.FullName }
& "$bt\d8.bat" --lib $jar --min-api 29 --classpath build\classes --output build\dex @cls
if ($LASTEXITCODE -ne 0) { throw "d8 failed: $LASTEXITCODE" }

Write-Host '== aapt2 link =='
& "$bt\aapt2.exe" link -o build\base.apk --manifest AndroidManifest.xml -I $jar -A assets --min-sdk-version 29 --target-sdk-version 34
if ($LASTEXITCODE -ne 0) { throw "aapt2 link failed: $LASTEXITCODE" }

Write-Host '== add classes.dex =='
Copy-Item build\base.apk build\unsigned.apk -Force
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open((Resolve-Path 'build\unsigned.apk'), 'Update')
[System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, (Resolve-Path 'build\dex\classes.dex'), 'classes.dex', [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
$zip.Dispose()

Write-Host '== zipalign =='
& "$bt\zipalign.exe" -f 4 build\unsigned.apk build\aligned.apk
if ($LASTEXITCODE -ne 0) { throw "zipalign failed: $LASTEXITCODE" }

Write-Host '== keystore =='
if (-not (Test-Path 'dtguard.jks')) {
  & keytool -genkeypair -v -keystore dtguard.jks -alias dtguard -keyalg RSA -keysize 2048 -validity 10000 `
    -storepass dtguard123 -keypass dtguard123 -dname 'CN=DeepTestGuard, OU=dualos, O=dualos, L=CN, ST=CN, C=CN'
  if ($LASTEXITCODE -ne 0) { throw "keytool failed: $LASTEXITCODE" }
}

Write-Host '== apksigner =='
& "$bt\apksigner.bat" sign --ks dtguard.jks --ks-pass pass:dtguard123 --key-pass pass:dtguard123 `
  --out DeepTestGuard.apk build\aligned.apk
if ($LASTEXITCODE -ne 0) { throw "apksigner failed: $LASTEXITCODE" }

& "$bt\apksigner.bat" verify --print-certs DeepTestGuard.apk
Get-Item DeepTestGuard.apk | Select-Object FullName, Length
