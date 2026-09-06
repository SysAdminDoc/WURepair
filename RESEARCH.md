# WURepair research

## Executive Summary
WURepair is a Windows PowerShell 5.1 script and module for local Windows Update recovery. It covers damaged services, caches, policy blockers, network failures, component-store corruption, and servicing-stack trouble. Version 2.32.1 includes the trust work identified in this review: a no-admin demo, diagnostics-backed preview, managed-policy protection, readiness gates, rollback journals, local HTML and JSON evidence, redacted support bundles, complete local tests, and consumer-side package verification with portable receipts.

The project should keep its repair focus. A resident agent, cloud dashboard, or broad patch manager would make privileged behavior harder to audit. The next useful improvements are Windows Event Forwarding support, a signed release path when a certificate is available, and an optional native interface that preserves the same preview and evidence model.

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
- Local checks now run the full Pester suite, report tool versions, and enforce tested minimums.
- Pending reboot and BitLocker conditions now feed a repair-readiness gate before unattended repair continues.
- Restore-point attempts and outcomes appear in JSON reports and support-bundle manifests.
- Contract tests keep script, module, help, command-line parsing, and README options aligned.
- JSON and support-bundle shapes have fixture tests for downstream automation.
- Release verification now checks ZIP hashes, package contents, optional catalogs, script signatures, and module import from an extracted consumer copy.
- Intune detection and remediation scripts keep their return-code and privacy contracts separate.
- Recovery work now includes preview, safe-mode handling, WinRE and Quick Machine Recovery diagnostics, DISM source fallback, journals, and redaction. Windows Event Forwarding remains the main evidence gap.

## Architecture Assessment
- Keep the script-first architecture: `WURepair.psm1` shells to `WURepair.ps1`, preserving CLI behavior for module users and avoiding a high-risk rewrite.
- Contract tests now cover script parameters, module forwarding, command aliases, help text, README options, JSON schemas, the support-bundle manifest, release receipts, and packaged artifacts.
- The remaining refactor candidate is shared option metadata. `Start-WURepair`, `Show-Help`, module forwarding, and the README still repeat parts of the public command surface.
- The main test gap is a disposable administrator-level Windows VM for destructive phase integration. Local tests cover parsing, contracts, reports, preview behavior, and release consumption.
- The README now explains preview, readiness gates, rollback, reporting, Intune use, package checksums, and signature expectations. Windows Event Forwarding needs documentation when that feature ships.
- Accessibility: `-PlainText` is the right CLI accessibility path; future GUI work should wait behind preview/reporting/trust items already in the roadmap.
- i18n/l10n: no UI localization is recommended now; correctness work should stay focused on endpoint manifests and structured parsing because repair output is operator-facing English.
- Observability: transcript capture, schema-stable reports, readiness status, restore-point status, WEF-ready event IDs, and support-bundle manifests fit the project better than a resident agent.
- Distribution and upgrades: consumer-side package verification and validation-tool version contracts now ship. Gallery pre-validation and signed update checks remain appropriate future work; GitHub Actions build and test workflows remain rejected by repo policy.
- Plugin ecosystem, mobile, multi-user, and cloud sync are rejected because WURepair is privileged local repair tooling; RMM/Intune should consume exported scripts/reports rather than delegate privileged mutation through plugins or a hosted service.

## Rejected Ideas
- Full patch manager from PSWindowsUpdate/WuMgr/commercial platforms: one-shot pending visibility is useful, but install/hide/uninstall policy belongs to dedicated update managers.
- Broad Windows repair suite modeled on Tweaking.com Windows Repair: too much ACL/registry blast radius for a Windows Update-focused repair tool.
- Resident background agent or cloud dashboard from commercial RMM products: conflicts with WURepair's on-demand, auditable, local-elevation trust model.
- Automatic BitLocker suspension: BitLocker status/readiness reporting is useful, but suspending encryption should remain an explicit operator action or separately named switch because it changes device security posture.
- Plugin system for repair phases from adjacent sysadmin tooling: administrator-level mutation hooks would increase support and security risk more than they help.
- Mobile companion app: no credible repair path because required operations need local administrator access to Windows.
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
- None block prioritization. Implementation should still be validated on a Windows 10 or 11 VM running Windows PowerShell 5.1 as administrator. Test both BitLocker states, System Restore states, mounted repair media, a downloaded release ZIP, and an Intune-like 64-bit host.
