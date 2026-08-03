# WURepair Roadmap

Forward-looking scope for the Windows Update repair tool. Everything below is tentative — issues and PRs welcome.

## Planned Features

### Diagnostics

### Repair Engines

### Reporting

### Packaging

## Competitive Research
- **Reset Windows Update Tool (wureset.com)** — 18-choice menu is the closest analogue; WURepair already wins on LTSC/IoT detection, but should copy the discrete "reset policies" menu item.
- **Tweaking.com Windows Repair** — adds permission repair + Safe-Mode re-run prompts; consider an `-InSafeMode` detection path that unlocks deeper file unlocks.
- **Update Fixer (winupdatefixer.com)** — markets itself as a precision tool; mirror its "what's wrong / what we'll do" preview before executing, gated behind a `-WhatIf`-style dry run.
- **WuMgr / Windows Update MiniTool** — selective KB install/block would turn WURepair into patch management; keep only a one-shot `-ListPending` that surfaces available updates post-repair.

## Nice-to-Haves
- WinRE offline repair mode: stage the script to an ISO/USB for running against an offline Windows volume via DISM `/Image:`.
- GUI wrapper (WPF, matches the rest of the SysAdminDoc stack) that surfaces each phase as a toggle with live progress.
- Integration with Windows Event Forwarding so enterprise SOC pipelines can subscribe to `WURepair` events.
- Self-update check against GitHub Releases when run with `-CheckForUpdates`.
- Hash-verified DLL re-registration: skip `regsvr32` when the DLL's Authenticode hash matches the expected catalog entry.

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
- Generated HTML report table per repair run with per-step pass/fail (taylornrolyat)
- WSUS client reset: flush `AccountDomainSid`, `PingID`, `SusClientId`, re-register against WSUS server
- WUfB diag log collection via `Get-WindowsUpdateLog` + zipped upload folder

### Patterns & Architectures Worth Studying
- PowerShell-only, EXE-free approach for policy-locked environments (AdmiralEM)
- Phased repair pipeline: Diagnose → Stop services → Rebuild stores → Start services → Verify (ManuelGil)
- Transcript logging (`Start-Transcript`) with a timestamped folder per run for support escalation
- Exit-code discipline: each phase returns a distinct code so orchestrators can branch
- Idempotency: each action checks current state before mutating, safe to re-run


