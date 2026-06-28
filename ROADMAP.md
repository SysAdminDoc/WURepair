# WURepair Roadmap

Forward-looking scope for the Windows Update repair tool. Everything below is tentative — issues and PRs welcome.

## Planned Features

### Diagnostics

### Repair Engines

### Reporting
- `-Unattended` mode: no host UI, no `Write-Host`, exit codes mapped to phase outcomes so it composes cleanly in PDQ/Intune/Tanium.
- Intune proactive remediation detection + remediation script pair generated from the existing phases.

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

- [ ] P0 - Replace blocking service cmdlets with timeout-safe service control
  Why: Current `Start-Service` / `Stop-Service` calls can block or surface host UI in silent automation, undermining the existing unattended/RMM roadmap item.
  Evidence: `WURepair.ps1:1848`, `WURepair.ps1:2139`, `WURepair.ps1:2185`, `WURepair.ps1:2199`; PowerShell stack convention; Intune remediations docs.
  Touches: `WURepair.ps1` service helpers and any phase that starts/stops services.
  Acceptance: No `Start-Service`, `Stop-Service`, `Restart-Service`, or `Set-Service -Status` calls remain; each service operation has a timeout, logs stdout/stderr, and reports success/failure to the phase result model.
  Complexity: M

- [ ] P0 - Return real phase statuses instead of unconditional completion
  Why: JSON reports and event logs must not mark failed or partially failed repairs as completed.
  Evidence: `WURepair.ps1:3788` phase loop; `WURepair.ps1:3849` JSON report; commercial patch/RMM tools treat exit/result fidelity as core value.
  Touches: `Start-WURepair`, `Write-JsonRepairReport`, `Write-RepairEventLog`, each repair function return path.
  Acceptance: Each phase returns `Success`, `Skipped`, `Changed`, `Warnings`, and `Errors`; JSON/event output reflects those fields; failed phases produce non-success automation exit codes once the existing unattended item lands.
  Complexity: L

- [ ] P0 - Add local Pester and PSScriptAnalyzer validation harness
  Why: A privileged system-repair script needs automated parser, lint, and mocked behavior coverage before signed releases or PSGallery packaging.
  Evidence: no tracked tests/manifests; Pester docs; PSScriptAnalyzer project; PSGallery publishing guidance.
  Touches: `tests/`, `WURepair.ps1`, optional `Invoke-LocalChecks.ps1` helper.
  Acceptance: A local command runs parser validation, PSScriptAnalyzer, and Pester tests with mocks for registry, service, filesystem, process, Catalog, DISM, and HRESULT parsing paths.
  Complexity: L

- [ ] P1 - Add a mutation journal and rollback helper for destructive repairs
  Why: Backups exist, but operators need a single machine-readable record of every hosts, registry, cache, and policy mutation and how to reverse it.
  Evidence: `WURepair.ps1:1700`, `WURepair.ps1:1918`, `WURepair.ps1:2284`, `WURepair.ps1:2385`; Microsoft troubleshooting docs emphasize reversible repair steps.
  Touches: hosts repair, policy repair, cache reset, registry reset, JSON report schema, log output.
  Acceptance: Each mutation appends before/after metadata to a run journal; `-RollbackJournal <path>` previews and applies reversible changes without guessing from text logs.
  Complexity: L

- [ ] P1 - Verify Catalog downloads before installing SSU packages
  Why: The Catalog repair path downloads elevated installers and should verify signature/catalog/hash before invoking `wusa.exe`.
  Evidence: `WURepair.ps1:2931`, `WURepair.ps1:2941`; Microsoft `about_Signing`; `Test-FileCatalog` docs.
  Touches: `Invoke-MicrosoftUpdateCatalogDownload`, `Invoke-ServicingStackMsuInstall`, logging/reporting.
  Acceptance: Downloaded `.msu` files are Authenticode/catalog validated, optionally hash-recorded in JSON, and skipped with a clear error when validation fails.
  Complexity: M

- [ ] P1 - Add managed update-source guardrails before policy removal
  Why: Enterprise WSUS/SUP/WUfB/Intune devices can have valid policy; WURepair should not remove managed source policy without an explicit repair mode.
  Evidence: current WSUS diagnostics in `WURepair.ps1:1197`; policy removal in `WURepair.ps1:1896`; Microsoft Intune remediations and Windows Update for Business guidance.
  Touches: `Get-WSUSPostureDiagnostic`, `Repair-UpdatePolicies`, repair plan preview, JSON report.
  Acceptance: Managed-source detection classifies likely corporate policy, defaults to diagnose-only for those values, and requires a named switch to remove or reset them.
  Complexity: M

- [ ] P1 - Produce a redacted support bundle
  Why: Logs are useful locally, but support escalation needs one zip with WU, CBS, DISM, USO, event, and JSON artifacts plus basic redaction.
  Evidence: existing JSON report at `WURepair.ps1:3498`; existing WU error parsing at `WURepair.ps1:587`; Microsoft `Get-WindowsUpdateLog` docs; existing roadmap WUfB diagnostic-log note.
  Touches: diagnostics, logging, JSON report, optional zip packaging.
  Acceptance: `-SupportBundle <path>` creates a zip containing WURepair log, JSON report, WindowsUpdate.log, relevant event exports, CBS/DISM tails, and a manifest; usernames/device identifiers are redacted unless `-NoRedact` is supplied.
  Complexity: M

- [ ] P2 - Add plain-text automation output mode
  Why: Colorized host UI is useful interactively, but screen readers, logs, and RMM consoles need stable plain text without bullets, progress bars, or color-only status.
  Evidence: `Write-Host` UI helpers at `WURepair.ps1:245` through `WURepair.ps1:479`; Intune output constraints; accessibility requirement for non-color status.
  Touches: UI helper functions, `Write-Log`, progress handling, help text.
  Acceptance: `-PlainText` emits deterministic ASCII status lines, suppresses progress rendering, keeps all status words explicit, and is covered by output snapshot tests.
  Complexity: S

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
