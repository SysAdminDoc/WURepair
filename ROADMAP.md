# WURepair Roadmap

Forward-looking scope for the Windows Update repair tool. Everything below is tentative — issues and PRs welcome.

## Planned Features

### Diagnostics
- Parse `%WINDIR%\WindowsUpdate.log` and `wuauclt` ETW traces into a ranked error summary (top 10 recurring HRESULTs with KB article links).
- Surface WaaSMedic diagnostics and `dosvc` DeliveryOptimization status (peer cache health, byte counts) alongside service state.
- Detect Microsoft Update Health Tools / Remediation service presence and whether sedlauncher/sedsvc are running.
- WSUS/SUP posture check: resolve `WUServer` / `WUStatusServer` URLs, `TargetGroup`, `UseWUServer`, disabled dual-scan policy.

### Repair Engines
- Add `-RepairWaaS` switch to reset Update Orchestrator and USO tasks (`\Microsoft\Windows\UpdateOrchestrator\*`).
- Add `-RepairDelivery` to reset DO cache folder (`C:\Windows\SoftwareDistribution\DeliveryOptimization`) and `DeliveryOptimizationDownloadMode` policy.
- Optional Dynamic Update pull: stage the latest servicing stack (SSU) MSU before attempting DISM RestoreHealth.
- Side-by-side component store analysis via `DISM /AnalyzeComponentStore` with auto-trigger of `StartComponentCleanup /ResetBase` when the reported delta exceeds a threshold.
- `ServicingStack` repair path: download matching SSU from Microsoft Update Catalog when `wusa /install` fails with 0x800f0922.

### Reporting
- Optional `-JsonReport <path>` writing the pre/post diagnostic delta as machine-parseable JSON for RMM ingestion.
- `-Unattended` mode: no host UI, no `Write-Host`, exit codes mapped to phase outcomes so it composes cleanly in PDQ/Intune/Tanium.
- Intune proactive remediation detection + remediation script pair generated from the existing phases.

### Packaging
- Signed script variant with embedded Authenticode signature and a release workflow that runs `Set-AuthenticodeSignature` with a hardware token.
- PSGallery module wrapper (`Install-Module WURepair`) exposing each repair phase as its own advanced function.

## Competitive Research
- **Reset Windows Update Tool (wureset.com)** — 18-choice menu is the closest analogue; WURepair already wins on LTSC/IoT detection, but should copy the discrete "reset policies" menu item.
- **Tweaking.com Windows Repair** — adds permission repair + Safe-Mode re-run prompts; consider an `-InSafeMode` detection path that unlocks deeper file unlocks.
- **Update Fixer (winupdatefixer.com)** — markets itself as a precision tool; mirror its "what's wrong / what we'll do" preview before executing, gated behind a `-WhatIf`-style dry run.
- **WuMgr / Windows Update MiniTool** — selective KB install/block; out of scope for repair but worth a one-shot `-ListPending` that surfaces available updates post-repair.

## Nice-to-Haves
- WinRE offline repair mode: stage the script to an ISO/USB for running against an offline Windows volume via DISM `/Image:`.
- GUI wrapper (WPF, matches the rest of the SysAdminDoc stack) that surfaces each phase as a toggle with live progress.
- Integration with Windows Event Forwarding so enterprise SOC pipelines can subscribe to `WURepair` events.
- Self-update check against GitHub Releases when run with `-CheckForUpdates`.
- Hash-verified DLL re-registration: skip `regsvr32` when the DLL's Authenticode hash matches the expected catalog entry.
- Locale-aware hosts cleanup covering regional Microsoft update endpoints (`*.tlu.dl.delivery.mp.microsoft.com` et al.).

## Open-Source Research (Round 2)

### Related OSS Projects
- https://github.com/ManuelGil/Script-Reset-Windows-Update-Tool — ResetWUEng.cmd reference, full component reset
- https://github.com/ManuelGil/Reset-Windows-Update-Tool — original C++ Dev-C++ edition
- https://github.com/wureset-tools/script-wureset — actively maintained fork, MIT
- https://github.com/iamtraction/fix-windows-update — minimal fix-stuck-update script
- https://github.com/ErenElagz/Windows-Update-Fix — DISM/SFC wrapper
- https://github.com/AdmiralEM/windows-update-repair — PowerShell-only, no EXE dependencies
- https://github.com/taylornrolyat/Repair-WindowsUpdates — silent, non-rebooting, Win7+Win10 aware
- https://github.com/Ec-25/FixIt — broader Windows optimization with WU repair subset
- https://gist.github.com/74Thirsty/18e2b9152c0ca3a2f5d76dcd1b5d6ff4 — WinSxS/Component Store deep-repair recipe

### Features to Borrow
- Silent non-rebooting mode for RMM / fleet runs (taylornrolyat)
- Generated HTML report table per repair run with per-step pass/fail (taylornrolyat)
- Service startup-type enforcement for BITS, cryptsvc, msiserver, wuauserv (taylornrolyat)
- Component Store repair path: DISM /StartComponentCleanup /ResetBase after /RestoreHealth (74Thirsty gist)
- WSUS client reset: flush `AccountDomainSid`, `PingID`, `SusClientId`, re-register against WSUS server
- catroot2 rebuild sequence gated by net-stop of cryptsvc (ManuelGil)
- SoftwareDistribution rename-then-recreate vs delete — safer under policy lock (AdmiralEM)
- WUfB diag log collection via `Get-WindowsUpdateLog` + zipped upload folder
- Offline CBS repair by pointing DISM `/Source:` to a mounted ISO `install.wim` (74Thirsty)
- Delivery Optimization cache flush step (`dosvc` + `%SystemRoot%\SoftwareDistribution\DeliveryOptimization`)

### Patterns & Architectures Worth Studying
- PowerShell-only, EXE-free approach for policy-locked environments (AdmiralEM)
- Phased repair pipeline: Diagnose → Stop services → Rebuild stores → Start services → Verify (ManuelGil)
- Transcript logging (`Start-Transcript`) with a timestamped folder per run for support escalation
- Exit-code discipline: each phase returns a distinct code so orchestrators can branch
- Idempotency: each action checks current state before mutating, safe to re-run
