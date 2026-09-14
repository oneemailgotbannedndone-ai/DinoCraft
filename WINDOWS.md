# DinoCraft on Windows: test build

This is the first step of bringing DinoCraft to Windows. It **doesn't open the game yet**.
It builds the part of DinoCraft that creates worlds, terrain, caves, lighting, physics,
crafting and saves, then runs 129 checks on it. If those pass on Windows, the next
steps add the window, graphics, sound and multiplayer.

Takes about 30–60 minutes the first time, mostly waiting for downloads.

## 1. Install the tools (one time)

Open **PowerShell** (Start menu → type "PowerShell") and run these one at a time.
Accept any prompts that appear.

```powershell
winget install --id Microsoft.VisualStudio.2022.Community --exact --force --custom "--add Microsoft.VisualStudio.Component.Windows11SDK.22621 --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64"
```

```powershell
winget install --id Swift.Toolchain -e
```

Then **restart the PC**.

Check it worked by opening PowerShell again and running:

```powershell
swift --version
```

It should print a Swift version (6.0 or newer). If a command above fails, follow the
official guide at <https://www.swift.org/install/windows/> instead, then continue here.

## 2. Build and run the test

1. Right-click `DinoCraft-windows-test.zip` → **Extract All…** → type `C:\` as the destination → **Extract**.
   You should now have a folder `C:\DinoCraft` with `Package.swift` inside it.
2. In PowerShell:

```powershell
cd C:\DinoCraft
swift build -c release --product DinoCraftSelfTest *> build.txt
.build\release\DinoCraftSelfTest.exe *> result.txt
```

## 3. Send the results back

Send **`build.txt`** and **`result.txt`** (both in `C:\DinoCraft`). If the build failed,
`result.txt` may be empty or missing. That's fine: `build.txt` has the error.

A successful run ends with a line like:

```
DinoCraftCore self-test: 129 passed, 0 failed
```
