# Creates two tablet AVDs (Tablet_7inch, Tablet_10inch) by writing their
# config files directly. Uses the only installed system image:
#   android-36.1;google_apis_playstore;x86_64
#
# Specs:
#   Tablet_7inch  -> 1200x1920 @ 320 dpi  (~7.05" diagonal, Nexus-7-class)
#   Tablet_10inch -> 1600x2560 @ 280 dpi  (~10.78" diagonal, Pixel-Tablet-class)

$avdRoot   = "$env:USERPROFILE\.android\avd"
$sysImage  = "system-images\android-36.1\google_apis_playstore\x86_64\"

function New-TabletAvd {
    param(
        [string]$Name,
        [string]$DisplayName,
        [int]   $Width,
        [int]   $Height,
        [int]   $Density,
        [int]   $RamMB
    )
    $avdDir = Join-Path $avdRoot "$Name.avd"
    $iniPath = Join-Path $avdRoot "$Name.ini"
    if (-not (Test-Path $avdDir)) { New-Item -ItemType Directory -Path $avdDir | Out-Null }

    # Top-level pointer .ini (must be ASCII, no BOM)
    $iniContent = @"
avd.ini.encoding=UTF-8
path=$avdDir
path.rel=avd\$Name.avd
target=android-36.1
"@
    [System.IO.File]::WriteAllText($iniPath, $iniContent, [System.Text.UTF8Encoding]::new($false))

    # config.ini
    $configContent = @"
AvdId=$Name
PlayStore.enabled=true
abi.type=x86_64
avd.ini.displayname=$DisplayName
avd.ini.encoding=UTF-8
disk.dataPartition.size=6G
fastboot.chosenSnapshotFile=
fastboot.forceChosenSnapshotBoot=no
fastboot.forceColdBoot=no
fastboot.forceFastBoot=yes
hw.accelerometer=yes
hw.arc=false
hw.audioInput=yes
hw.battery=yes
hw.camera.back=virtualscene
hw.camera.front=emulated
hw.cpu.arch=x86_64
hw.cpu.ncore=4
hw.dPad=no
hw.gps=yes
hw.gpu.enabled=yes
hw.gpu.mode=auto
hw.gyroscope=yes
hw.initialOrientation=portrait
hw.keyboard=yes
hw.lcd.density=$Density
hw.lcd.height=$Height
hw.lcd.width=$Width
hw.mainKeys=no
hw.ramSize=$RamMB
hw.sdCard=yes
hw.sensors.light=yes
hw.sensors.magnetic_field=yes
hw.sensors.orientation=yes
hw.sensors.pressure=yes
hw.sensors.proximity=yes
hw.trackBall=no
image.sysdir.1=$sysImage
runtime.network.latency=none
runtime.network.speed=full
sdcard.size=512M
showDeviceFrame=no
skin.dynamic=yes
skin.name=${Width}x${Height}
skin.path=_no_skin
tag.display=Google Play
tag.displaynames=Google Play
tag.id=google_apis_playstore
tag.ids=google_apis_playstore
target=android-36.1
vm.heapSize=384
"@
    [System.IO.File]::WriteAllText((Join-Path $avdDir 'config.ini'), $configContent, [System.Text.UTF8Encoding]::new($false))

    "Created $Name -> $avdDir  ($Width x $Height @ ${Density}dpi)"
}

New-TabletAvd -Name 'Tablet_7inch'  -DisplayName 'Tablet 7 inch'  -Width 1200 -Height 1920 -Density 320 -RamMB 2048
New-TabletAvd -Name 'Tablet_10inch' -DisplayName 'Tablet 10 inch' -Width 1600 -Height 2560 -Density 280 -RamMB 3072

""
"--- AVD list now ---"
& "$env:LOCALAPPDATA\Android\Sdk\emulator\emulator.exe" -list-avds
