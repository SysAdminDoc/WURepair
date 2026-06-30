# Research — WURepair

## Executive Summary
Verified: WURepair is a Windows PowerShell 5.1 Windows Update repair script for elevated, local recovery of update services, stores, policy damage, network/TLS blockers, component store corruption, and servicing stack failures. Its strongest current shape is automation-safe repair: timeout-safe service control, phase statuses and exit codes, JSON reporting, mutation rollback, managed WSUS/WUfB guardrails, verified Catalog SSU installs, support bundles, and plain-text output are already present in `WURepair.ps1`, `Invoke-LocalChecks.ps1`, and `tests/WURepair.Static.Tests.ps1`. Highest-value direction: finish enterprise distribution, behavior verification, and operator-trust gaps without turning the tool into a patch manager. Priority opportunities: add ISO/WIM/ESD-backed DISM source fallback; generate Intune remediation packages with Intune script-host constraints; expand behavior-level tests beyond static contracts; emit structured Windows Update log timelines; ship signed/module packaging metadata with release verification receipts; move endpoint/policy lists into a versioned manifest; and add WinRE/Quick Machine Recovery diagnostics.

## Product Map
- Core workflows: diagnostic pre-check; repair plan preview; service/cache/policy/network/DISM/SFC/WaaS/Delivery Optimization repairs; optional SSU staging or Microsoft Update Catalog SSU repair; before/after verification with log, event, JSON, support bundle, and rollback journal.
- User personas: home power user recovering from privacy/debloat tools; MSP/RMM technician running unattended repair; Intune/ConfigMgr/WSUS administrator preserving managed update policy; maintainer publishing signed PowerShell artifacts.
- Platforms and distribution: Windows 10/11 including LTSC/IoT; Windows PowerShell 5.1; GitHub Release ZIP today; planned Authenticode and PowerShell Gallery module delivery; no tracked module manifest, file catalog, or checksum receipt yet.
- Key integrations and data flows: Windows services, registry, scheduled tasks, hosts file, DISM/SFC/wusa/UsoClient, Windows Update Agent COM, Microsoft Update Catalog, Windows Update ETW/log conversion, Windows event logs, local JSON/support bundle outputs.

## Competitive Landscape
- Reset Windows Update Tool / script-wureset: broad menu-driven component reset and multilingual ecosystem; learn explicit action grouping and discrete policy reset, but avoid interactive-only menus because WURepair's advantage is unattended/RMM-safe execution.
- PSWindowsUpdate: mature PowerShell Gallery module for scan/install/history/settings and `Reset-WUComponents`; learn module packaging, WUA abstractions, reboot-aware update queries, and AllSigned failure modes from its signing issue queue, but avoid becoming a general update installer/blocker.
- WuMgr: uses Windows Update Agent API for scan/download/install/hide flows and shows the demand for `-ListPending`; learn one-shot pending update visibility, but avoid GUI patch-management state that WURepair cannot own safely.
- IAmLegionVaal/Windows-Update-Repair: small PowerShell repair script with `-WhatIf`, service-state restoration, transcript/log directory, WUA search, and simple exit codes; learn native preview semantics and final service-state restoration, but avoid GitHub Actions as the local policy forbids remote CI.
- taylornrolyat/Repair-WindowsUpdates: WSUS-oriented silent repair with CSV remoting and end report table; learn WSUS/SUS client identity repair and generated report shape, but avoid deleting stores without WURepair's rollback/journal protections.
- AdmiralEM/windows-update-repair: transparent step-by-step PowerShell scripts for locked-down environments; learn modular phase boundaries and dry-run future plan, but avoid scattering the primary UX across many entry points.
- Commercial patch platforms (Action1, NinjaOne, ManageEngine, PDQ): their paywalled value is remote execution, compliance/reporting, reboot handling, and deployment targeting; WURepair should export artifacts and reports these tools can consume, not duplicate multi-tenant patch management.
- Microsoft platform docs: official guidance anchors DISM source repair, Get-WindowsUpdateLog, Intune remediation scripts, Windows Update Agent API, Delivery Optimization, signing, and PowerShell Gallery publishing; WURepair should keep implementation tied to those documented APIs.

## Security, Privacy, and Reliability
- Verified: `WURepair.ps1:4099` runs `DISM /Online /Cleanup-Image /RestoreHealth` without a `-Source` or `/LimitAccess` path, so a machine whose Windows Update repair source is blocked has no local ISO/WIM/ESD fallback.
- Verified: `WURepair.ps1:1079` and `WURepair.ps1:1174` convert Windows Update logs and summarize HRESULTs, but no structured timeline export exists for "no error shown" or wrong-success cases seen in PSWindowsUpdate and WuMgr issue queues.
- Verified: `WURepair.ps1:102` and `WURepair.ps1:2481` still keep endpoint and policy knowledge inside imperative code; the existing roadmap's versioned endpoint/policy manifest remains valid and should reduce risky drift.
- Verified: no `.psd1`, `.psm1`, `.nuspec`, `.ps1xml`, file catalog, or tracked checksum receipt exists, so the signed/module packaging roadmap item must include module metadata, artifact verification, and local packaging checks before a PowerShell Gallery release.
- Verified: `dist/WURepair-v2.17.0.zip` exists locally but no tracked release receipt or verification command accompanies it; PSWindowsUpdate issue 63 and Microsoft `New-FileCatalog` guidance show why non-script assets need catalog/checksum coverage in AllSigned environments.
- Verified: `tests/WURepair.Static.Tests.ps1:1` is a valuable static/mocked contract suite, but it does not exercise the CLI parser, full phase planning, version drift, or behavior fixtures for DISM source and future Intune packaging.
- Verified: `Roadmap_Blocked.md` already exists and is ignored; this research pass did not create or modify it.
- Missing guardrails: Intune remediation generation must honor detection/remediation separation, exit-code semantics, 64-bit host choice, output-size constraints, and redaction rather than wrapping the full interactive script unchanged.
- Missing guardrails: release packaging must verify every delivered file, including future `.psd1`, `.psm1`, `.ps1xml`, support data, and ZIP contents, not only the top-level script signature.
- Recovery needs: DISM source fallback should validate mounted images and indexes before repair; structured log export should redact identifiers and cross-link logs, JSON report, support bundle, and event IDs.

## Architecture Assessment
- Keep the script-first architecture until a module wrapper lands; extracting all logic now would create churn, but packaging can expose advanced functions that call the stable script entry point.
- Add focused boundaries before new features: DISM argument builder/source validator, Intune package generator, Windows Update log parser/exporter, endpoint/policy manifest loader, and packaging/version validator.
- Test gaps are now more important than raw feature gaps: add behavior-level Pester tests with mocked process/registry/filesystem/WUA calls and version/package drift checks in `Invoke-LocalChecks.ps1`.
- Documentation gaps: README covers current switches, but future packaging work must document signed ZIP/module install, signature verification, and Intune artifact usage without adding new markdown files.
- Accessibility: current `-PlainText` is the correct CLI path; future GUI work should not precede the already-planned dry-run/listing/reporting tasks.
- i18n/l10n: do not localize the CLI yet; instead, add locale-aware endpoint manifests and size/log parsing because those affect repair correctness.
- Observability: structured Windows Update log timeline and WEF-ready event schema are better fits than a resident agent.
- Distribution/upgrade: Authenticode signing, PowerShell Gallery manifest metadata, file catalog or SHA256 verification receipts, release ZIP verification, and optional self-update signature checks are appropriate; GitHub Actions build workflows are not.
- Migration path: the PowerShell Gallery module wrapper should preserve the current script CLI, exit codes, JSON schema, and support-bundle layout so RMM/Intune callers can move gradually instead of rewriting automations.
- Plugin ecosystem, mobile, multi-user, and cloud sync are rejected because WURepair is privileged local repair tooling; RMM and Intune should consume exported scripts/reports rather than delegate execution to plugins or a central service.

## Rejected Ideas
- Full patch manager from PSWindowsUpdate/WuMgr sources: WURepair should only list pending updates after repair; install/hide/uninstall workflows belong to dedicated update managers.
- Broad Windows repair suite modeled on Tweaking.com: too much registry/ACL blast radius for a focused Windows Update repair tool.
- Resident background agent: commercial vendors show value, but WURepair's trust model is on-demand, auditable, elevated execution.
- Cloud dashboard or multi-tenant fleet portal: JSON/events/Intune artifacts are enough integration; storing endpoint state centrally would add privacy and operations burden.
- Plugin system for repair phases: extension hooks around elevated mutation paths would increase support and security risk more than they help.
- Mobile companion app: no credible local repair workflow because the required operations need elevated Windows access.
- Automatic driver/firmware repair: adjacent to update failures, but vendor tooling and Windows Update for Business policy own that domain.
- GitHub Actions validation copied from competitor repos: local policy forbids build/test workflows; keep `Invoke-LocalChecks.ps1` local.

## Sources
OSS competitors:
- https://github.com/wureset-tools/script-wureset
- https://github.com/ManuelGil/Script-Reset-Windows-Update-Tool
- https://github.com/ManuelGil/Reset-Windows-Update-Tool
- https://github.com/mgajda83/PSWindowsUpdate
- https://github.com/mgajda83/PSWindowsUpdate/issues/63
- https://github.com/DavidXanatos/wumgr
- https://github.com/DavidXanatos/wumgr/issues
- https://github.com/taylornrolyat/Repair-WindowsUpdates
- https://github.com/AdmiralEM/windows-update-repair
- https://github.com/IAmLegionVaal/Windows-Update-Repair
- https://github.com/elr484/windows-update-reset-gui

Microsoft/platform:
- https://learn.microsoft.com/en-us/intune/intune-service/fundamentals/remediations
- https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/repair-a-windows-image
- https://learn.microsoft.com/en-us/powershell/module/windowsupdate/get-windowsupdatelog
- https://learn.microsoft.com/en-us/windows/win32/wua_sdk/using-the-windows-update-agent-api
- https://learn.microsoft.com/en-us/windows/deployment/do/waas-delivery-optimization
- https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference
- https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_signing
- https://learn.microsoft.com/en-us/powershell/gallery/how-to/publishing-packages/publishing-a-package
- https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/new-filecatalog
- https://learn.microsoft.com/en-us/windows/configuration/quick-machine-recovery/
- https://learn.microsoft.com/en-us/windows/client-management/mdm/recovery-csp

Commercial/adjacent/community:
- https://www.action1.com/patch-management/
- https://www.ninjaone.com/patch-management/
- https://www.manageengine.com/patch-management/
- https://www.pdq.com/pdq-deploy/
- https://pester.dev/docs/usage/code-coverage
- https://github.com/PowerShell/PSScriptAnalyzer
- https://www.reddit.com/r/Intune/

## Open Questions
- None block prioritization. Implementation should still be validated on an elevated Windows 10/11 VM with Windows PowerShell 5.1, a mounted Windows ISO/WIM source, and an Intune-like 64-bit script host simulation.
