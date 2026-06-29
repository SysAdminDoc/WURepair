# WURepair Roadmap

Forward-looking scope for the Windows Update repair tool. Everything below is tentative — issues and PRs welcome.

## Planned Features

### Diagnostics

### Repair Engines

### Reporting
- Intune proactive remediation detection + remediation script pair generated from the existing phases.
  Research note: generated artifacts must honor Intune detection/remediation separation, stable exit codes, 64-bit PowerShell 5.1 hosting, concise/redacted output, and local JSON/support artifact writes.

### Packaging
- Signed script variant with embedded Authenticode signature and a release workflow that runs `Set-AuthenticodeSignature` with a hardware token.
- PSGallery module wrapper (`Install-Module WURepair`) exposing each repair phase as its own advanced function.

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

## Research-Driven Additions

- [ ] P2 - Add signed release and module packaging metadata
  Why: Existing roadmap names signing and PSGallery separately; implementation needs the manifests and local packaging checks that make those deliverable.
  Evidence: existing Packaging roadmap; PowerShell Gallery publishing docs; `about_Signing`; current tracked files lack `.psd1` or `.psm1` metadata.
  Touches: module wrapper, manifest, local packaging script, README release instructions when release work begins.
  Acceptance: Local packaging produces a signed script zip and a module artifact with version metadata, license tags, release notes, and analyzer/test checks before packaging.
  Complexity: L

- [ ] P3 - Add a versioned endpoint and policy knowledge manifest
  Why: Hosts and policy repair should evolve without scattering regional Microsoft endpoints and policy keys through imperative code.
  Evidence: Microsoft domain list in `WURepair.ps1:95`; policy list in `WURepair.ps1:1896`; existing locale-aware hosts cleanup note.
  Touches: endpoint/policy data definitions, hosts cleanup, policy repair, tests.
  Acceptance: Microsoft update domains and removable policy keys are defined in a versioned data block with source URLs, tests assert coverage for known regional endpoints, and repair code consumes the manifest instead of hard-coded loops.
  Complexity: M

- [ ] P1 — Add DISM source fallback for mounted ISO/WIM/ESD repairs
  Why: Machines with broken Windows Update sources can need local repair media before `RestoreHealth` succeeds.
  Evidence: Microsoft Repair a Windows Image docs; `WURepair.ps1:4099` runs `DISM /Online /Cleanup-Image /RestoreHealth` without `/Source` or `/LimitAccess`.
  Touches: `WURepair.ps1` `Invoke-DISM`, CLI option parsing, JSON report options, README usage, tests.
  Acceptance: `-DismSource <path>` accepts a mounted Windows image, WIM, or ESD source, optional `-DismLimitAccess` prevents WU source fallback, invalid sources fail before mutation, and tests verify generated DISM arguments plus JSON/report fields.
  Complexity: M

- [ ] P1 — Add behavior-level Pester fixtures and release drift checks
  Why: Current tests protect static contracts but do not exercise CLI parsing, full phase planning, version consistency, or future packaging/remediation artifacts.
  Evidence: `tests/WURepair.Static.Tests.ps1:1`; `Invoke-LocalChecks.ps1`; Pester and PSScriptAnalyzer docs.
  Touches: `tests/`, `Invoke-LocalChecks.ps1`, README/version assertions, package metadata when added.
  Acceptance: Local checks include behavior fixtures for CLI argument parsing, planned phase selection, DISM source arguments, version string consistency across tracked release files, and package/remediation artifact parse validation.
  Complexity: M

- [ ] P2 — Export a structured Windows Update log timeline
  Why: Ranked HRESULTs are useful, but support escalations often need timestamped component/message context for failures that show no clear UI error.
  Evidence: `WURepair.ps1:1079` `Get-WUConvertedTraceLogPath`; `WURepair.ps1:1174` `Get-WUErrorSummary`; PSWindowsUpdate and WuMgr issue queues include no-error/wrong-success complaints; Microsoft `Get-WindowsUpdateLog` docs.
  Touches: Windows Update log parser, JSON report schema, support bundle manifest, tests.
  Acceptance: `-AnalyzeLogs` or the support bundle emits `WURepair-wulog.json` with timestamp, component, level, code, message, and source file fields; JSON reports include a compact summary; redaction is applied consistently.
  Complexity: M

- [ ] P3 — Add WinRE and Quick Machine Recovery diagnostics
  Why: Offline/WinRE repair is already a roadmap direction, and diagnostics should show whether recovery infrastructure is available before a user needs it.
  Evidence: existing WinRE offline repair roadmap item; Microsoft Windows recovery/Quick Machine Recovery documentation; no `WinRE`, `reagentc`, or QMR probes currently appear in `WURepair.ps1`.
  Touches: diagnostics, JSON report, support bundle manifest, README troubleshooting, tests.
  Acceptance: Pre-check reports WinRE enabled/path/state, captures `reagentc /info` in support bundles, reports Quick Machine Recovery policy/status when available, and does not attempt cloud-managed recovery actions.
  Complexity: S
