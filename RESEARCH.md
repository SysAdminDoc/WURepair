# Research - WURepair

## Executive Summary
Verified: WURepair is a Windows PowerShell 5.1 Windows Update repair script/module for elevated local recovery of update services, stores, policies, network/TLS blockers, component-store corruption, servicing-stack failures, and diagnostic evidence collection. Its strongest current shape is automation-safe repair with timeout-safe `sc.exe` service control, JSON reports, redacted support bundles, mutation rollback journals, managed WSUS/WUfB guardrails, DISM source fallback, structured Windows Update log timelines, endpoint/policy manifests, module packaging, file catalogs, and local checks. Highest-value direction: strengthen operator trust and release contracts before adding more repair breadth. Priority opportunities: keep existing roadmap work for native `-WhatIf`, `-ListPending`, Intune, WEF, WinRE/QMR, GUI, and self-update; add repair-readiness gating for pending reboot/BitLocker risk; report system restore-point outcome in JSON/support artifacts; run every Pester test and pin validation-tool versions; enforce CLI/module/README option parity; schema-test JSON/support-bundle contracts; and verify release ZIPs from the consumer side.

## Product Map
- Core workflows: diagnostic pre-check; scoped/full repair planning; service/cache/policy/network/WaaS/Delivery Optimization/DISM/SFC/servicing-stack repair; Windows Update log analysis; JSON/support-bundle/rollback output.
- User personas: home power user recovering from privacy/debloat damage; MSP/RMM technician running unattended repairs; Intune/ConfigMgr/WSUS administrator preserving managed policy; maintainer publishing script/module release artifacts.
- Platforms and distribution: Windows 10/11 including LTSC/IoT; Windows PowerShell 5.1; GitHub ZIP/script/module artifacts via `tools/Build-WURepairPackage.ps1`; MIT license.
- Key integrations and data flows: Windows services, registry, hosts file, scheduled tasks, DISM/SFC/wusa/UsoClient/WUA COM, Microsoft Update Catalog, ETW-to-WindowsUpdate.log, Windows event logs, local JSON, support ZIP, SHA256/catalog release receipts.

## Competitive Landscape
- Reset Windows Update Tool / script-wureset: broad reset menu and separate reset/policy/WSUS utilities; learn explicit action grouping and WSUS identity repair, but avoid an interactive-only flow because WURepair's advantage is unattended repair.
- PSWindowsUpdate: mature Gallery module for scan/install/history/settings and `Reset-WUComponents`; learn WUA query surfaces, signing pitfalls, and correct `-WhatIf` semantics, but avoid becoming a general install/hide/uninstall patch manager.
- WuMgr: GUI update manager with strong pending-update visibility and offline/service options; WURepair should keep the existing roadmap's one-shot `-ListPending`, not persistent update-state management.
- IAmLegionVaal/Windows-Update-Repair: small PowerShell tool with `-WhatIf`, transcript/log directory, WUA search, and exit codes; learn native preview semantics and transcript evidence while keeping WURepair's stronger support-bundle/redaction model.
- taylornrolyat/Repair-WindowsUpdates and AdmiralEM/windows-update-repair: useful WSUS/reporting and PowerShell-only phase patterns; learn report clarity and modular phases, but keep WURepair's rollback and managed-policy guardrails.
- Commercial patch platforms (Action1, NinjaOne, ManageEngine, PDQ): paid value is remote targeting, compliance reporting, reboot handling, staged rollout, and package libraries; WURepair should export reliable artifacts these platforms can consume rather than duplicate fleet patch management.
- Microsoft platform docs: Intune Remediations, DISM source repair, WUA, Get-WindowsUpdateLog, WEF, QMR, restore points, BitLocker, signing, file catalogs, and Gallery publishing are the correct API boundaries for future work.

## Security, Privacy, and Reliability
- Verified bug/risk: `Invoke-LocalChecks.ps1:75` runs Pester through explicit `-FullNameFilter` batches; local execution discovered 36 tests but ran them in two filtered groups, so future tests can be silently skipped if names miss the allowlist.
- Verified bug/risk: `WURepair.ps1:5198` warns on pending reboot, but `Read-Confirmation -DefaultYes:$Unattended` at `WURepair.ps1:5224` means unattended/RMM runs can proceed through destructive phases with no explicit readiness gate.
- Verified bug/risk: `WURepair.ps1` has no BitLocker readiness probe, while Microsoft System Restore and BitLocker docs show recovery and update/servicing flows can require BitLocker key awareness.
- Verified bug/risk: `WURepair.ps1:5230`-`5240` attempts `Enable-ComputerRestore` and `Checkpoint-Computer`, but only logs success/failure; JSON reports and support bundles do not expose whether the promised restore point actually exists.
- Verified bug/risk: `WURepair.ps1:5010`, `WURepair.ps1:5482`, `WURepair.psm1:50`, and `README.md:149` duplicate public option surfaces; existing tests validate module metadata but not full option/help/README parity.
- Verified bug/risk: `Write-JsonRepairReport` hardcodes schema version and shape at `WURepair.ps1:4616`, and `New-WUSupportBundle` writes `manifest.json` at `WURepair.ps1:4928`; neither has schema/fixture compatibility tests for RMM/Intune/WEF consumers.
- Verified bug/risk: `tools/Build-WURepairPackage.ps1:150` signs scripts, `:151` creates catalogs, `:152` writes checksums, and `:216` writes a release receipt, but there is no consumer-side ZIP verification/import smoke.
- Missing guardrails: Intune package generation must respect detection/remediation separation, UTF-8 encoding, `exit 1` detection semantics, 2,048-character output, no reboot commands, and privacy guidance.
- Missing guardrails: validation tooling should report Pester/PSScriptAnalyzer versions and enforce tested minimums; Pester 5.8.0 shipped on 2026-06-30 while the repo currently accepts any Pester 5.x.
- Recovery and rollback needs: existing mutation journals and DISM source fallback are strong; remaining recovery work should add readiness gating, restore-point outcome reporting, native preview, safe-mode detection, WinRE/QMR diagnostics, and WEF-ready events before deeper offline mutation work.

## Architecture Assessment
- Keep the script-first architecture: `WURepair.psm1` shells to `WURepair.ps1`, preserving CLI behavior for module users and avoiding a high-risk rewrite.
- Add contract tests around public boundaries before adding flags: script parameters, module wrapper forwarding, CLI parser aliases, help text, README options, JSON report schema, support-bundle manifest, release receipt, and artifact contents.
- Refactor candidates: `Start-WURepair` readiness/restore-point handling (`WURepair.ps1:5198`-`5240`), public option metadata shared by `Start-WURepair`/`Show-Help`/README, JSON sample generation around `Write-JsonRepairReport`, and a package verifier next to `tools/Build-WURepairPackage.ps1`.
- Test gaps: local checks should run the full Pester suite by default, emit validation tool versions, and optionally produce Pester coverage without requiring online installs.
- Documentation gaps: README covers current switches, but package verification, restore-point outcome semantics, readiness-block behavior, support-bundle schemas, and future Intune/WEF artifacts need usage docs in existing files only.
- Accessibility: `-PlainText` is the right CLI accessibility path; future GUI work should wait behind preview/reporting/trust items already in the roadmap.
- i18n/l10n: no UI localization is recommended now; correctness work should stay focused on endpoint manifests and structured parsing because repair output is operator-facing English.
- Observability: transcript capture, schema-stable reports, readiness status, restore-point status, WEF-ready event IDs, and support-bundle manifests fit the project better than a resident agent.
- Distribution/upgrade: package verification, Gallery pre-validation, validation-tool version contracts, and signed self-update checks are appropriate; GitHub Actions build/test workflows remain rejected by repo policy.
- Plugin ecosystem, mobile, multi-user, and cloud sync are rejected because WURepair is privileged local repair tooling; RMM/Intune should consume exported scripts/reports rather than delegate privileged mutation through plugins or a hosted service.

## Rejected Ideas
- Full patch manager from PSWindowsUpdate/WuMgr/commercial platforms: one-shot pending visibility is useful, but install/hide/uninstall policy belongs to dedicated update managers.
- Broad Windows repair suite modeled on Tweaking.com Windows Repair: too much ACL/registry blast radius for a Windows Update-focused repair tool.
- Resident background agent or cloud dashboard from commercial RMM products: conflicts with WURepair's on-demand, auditable, local-elevation trust model.
- Automatic BitLocker suspension: BitLocker status/readiness reporting is useful, but suspending encryption should remain an explicit operator action or separately named switch because it changes device security posture.
- Plugin system for repair phases from adjacent sysadmin tooling: elevated mutation hooks would increase support and security risk more than they help.
- Mobile companion app: no credible repair path because required operations need local elevated Windows access.
- Full localization project: not enough user-facing UI surface; regional endpoint correctness is already better served by the shipped knowledge manifest.
- GitHub Actions validation copied from competitor repos: local policy forbids build/test workflows; keep verification in `Invoke-LocalChecks.ps1` and local packaging tools.

## Sources
OSS competitors and adjacent:
- https://github.com/wureset-tools/script-wureset
- https://github.com/mgajda83/PSWindowsUpdate
- https://github.com/mgajda83/PSWindowsUpdate/issues/28
- https://github.com/mgajda83/PSWindowsUpdate/issues/63
- https://github.com/DavidXanatos/wumgr
- https://github.com/IAmLegionVaal/Windows-Update-Repair
- https://github.com/taylornrolyat/Repair-WindowsUpdates
- https://github.com/AdmiralEM/windows-update-repair
- https://github.com/awesome-foss/awesome-sysadmin

Commercial, community, and engineering:
- https://www.action1.com/documentation/reports-and-update-statistic/
- https://www.ninjaone.com/docs/patch-management/os-patch-guide/
- https://www.manageengine.com/patch-management/windows-patch-management.html
- https://help.pdq.com/hc/en-us/articles/13615858339611-PDQ-Package-Library-and-the-PSWindowsUpdate-PowerShell-Module
- https://www.tweaking.com/content/page/windows_repair_all_in_one.html
- https://www.reddit.com/r/Intune/
- https://techcommunity.microsoft.com/event/windowsevents/troubleshooting-windows-updates/3971556

Microsoft/platform:
- https://learn.microsoft.com/en-us/intune/device-management/tools/deploy-remediations
- https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/repair-a-windows-image
- https://learn.microsoft.com/en-us/windows/win32/wua_sdk/searching--downloading--and-installing-updates
- https://learn.microsoft.com/en-us/powershell/module/windowsupdate/get-windowsupdatelog
- https://learn.microsoft.com/en-us/windows/win32/wec/windows-event-collector
- https://learn.microsoft.com/en-us/windows/configuration/quick-machine-recovery/
- https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/checkpoint-computer
- https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/enable-computerrestore
- https://learn.microsoft.com/en-us/powershell/module/bitlocker/suspend-bitlocker
- https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/new-filecatalog
- https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/test-filecatalog

Dependency and security:
- https://github.com/pester/Pester/releases/tag/5.8.0
- https://github.com/PowerShell/PSScriptAnalyzer/releases/tag/1.25.0
- https://github.com/PowerShell/PowerShell/security/advisories

## Open Questions
- None block prioritization. Implementation should still be validated on an elevated Windows 10/11 VM with Windows PowerShell 5.1, BitLocker enabled/disabled test cases, System Restore enabled/disabled/throttled cases, removable/mounted Windows media, a built release ZIP, and an Intune-like 64-bit host simulation.
