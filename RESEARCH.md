# Research - WURepair

## Executive Summary
WURepair is a single-file PowerShell 5.1 Windows Update repair tool for administrators recovering machines damaged by policy drift, privacy/debloat tools, service damage, cache corruption, or servicing-stack failure. Its strongest current shape is guided local repair with diagnostics, before/after comparison, optional SSU recovery, Delivery Optimization/WaaSMedic visibility, event logging, and JSON reporting. Highest-value direction: make the tool automation-safe and evidence-driven without turning it into a general patch manager. Top opportunities: replace blocking service cmdlets with timeout-safe wrappers; return real phase statuses instead of unconditional completion; add a local Pester/PSScriptAnalyzer harness; finish the unattended/exit-code contract already on the roadmap; add a support bundle for WU/CBS/DISM/USO logs; add managed-policy guardrails for WSUS/WUfB/Intune conflicts; hash/signature-verify downloaded Catalog payloads; add a rollback journal for destructive repairs; generate distribution metadata for signed script/module delivery.

## Product Map
- Core workflows: preflight diagnostics; guided repair plan; service/cache/policy/network/DISM/SFC repair phases; optional SSU staging or Catalog repair; post-repair comparison plus logs, event log, and JSON report.
- User personas: home power user recovering Windows Update after privacy tools; MSP/RMM technician; enterprise endpoint admin validating WSUS/WUfB/SUP posture; maintainer shipping signed PowerShell tooling.
- Platforms and distribution: Windows 10/11 including LTSC/IoT; Windows PowerShell 5.1; script-first distribution via GitHub Releases today, with roadmap interest in Authenticode and PSGallery.
- Key integrations and data flows: Windows services/registry/tasks; hosts file; DISM/SFC/wusa/UsoClient; Windows Update Agent COM; Microsoft Update Catalog; Windows event logs; optional JSON report for RMM ingestion.

## Competitive Landscape
- Reset Windows Update Tool / Script Reset Windows Update Tool: menu-driven reset coverage and discrete repair actions are useful; WURepair should learn the explicit action grouping, but avoid interactive-only menus that block RMM use.
- PSWindowsUpdate: exposes Windows Update Agent operations for scan/install/history; WURepair should learn from its WUA abstraction, but avoid becoming a full update installer/blocker.
- Intune remediation script collections: detection/remediation pairing and strict exit-code behavior are table stakes for fleet deployment; WURepair should adopt that contract, but avoid cloud-only assumptions.
- Tweaking.com Windows Repair: strong on safe-mode/deeper repair positioning and broad permission repair; WURepair should borrow safe-mode detection guidance, but avoid broad registry/ACL repair that can create unrelated risk.
- FixWin / Windows Update Fixer tools: quick single-click fixes and "what will change" previews lower operator fear; WURepair should keep the existing preview/dry-run idea, but avoid opaque black-box repairs.
- Microsoft Windows Update troubleshooting docs: official guidance emphasizes logs, DISM, WU error codes, reset components, and clear recovery steps; WURepair should keep references close to each diagnosis.
- Commercial patch managers (Action1, NinjaOne, ManageEngine, PDQ): automation, reporting, reboot handling, and package targeting are paywalled value; WURepair should cover local script hooks and reports, but not compete as a multi-tenant patch platform.

## Security, Privacy, and Reliability
- Verified: `WURepair.ps1:1848`, `WURepair.ps1:2139`, `WURepair.ps1:2185`, and `WURepair.ps1:2199` still use `Start-Service` / `Stop-Service`; stack conventions require `sc.exe` or equivalent timeout-safe service control for silent automation.
- Verified: `WURepair.ps1:3788` through the phase loop records each phase as `Status = 'Completed'` even when the action logs warnings or fails internally, so JSON/event consumers can receive false success.
- Verified: `WURepair.ps1:2284`, `WURepair.ps1:2305`, and `WURepair.ps1:2385` perform destructive file/registry cleanup without a machine-readable rollback journal that maps every mutation to a restore action.
- Verified: `Invoke-MicrosoftUpdateCatalogDownload` downloads Catalog payloads at `WURepair.ps1:2931`, but no Authenticode/catalog/hash validation is performed before `wusa.exe` installation at `WURepair.ps1:2941`.
- Verified: the working tree has v2.12.0/unattended edits in `WURepair.ps1`, while README and local working notes still describe v2.11.0; the research pass must not alter those files, but release work needs a version/doc sync.
- Verified: no tracked tests or package manifest exist; only `.gitignore`, `LICENSE`, `README.md`, `WURepair.ps1`, and icon assets are tracked.
- Likely: `Write-Progress` at `WURepair.ps1:3788` will still emit host UI during automation unless it is gated by unattended mode, because only the custom UI helpers were partially silenced in the current working tree.

## Architecture Assessment
- `WURepair.ps1` is about 4,000 lines with many global helpers; split only where it improves testability: service control, Catalog download/install, diagnostics, mutation/rollback journaling, and report serialization.
- Add a phase result contract where each repair function returns `Success`, `Skipped`, `Changed`, `Warnings`, and `Errors`; feed that into JSON, event logs, and exit codes instead of parsing text logs later.
- Add local-only validation: Pester tests with mocks for registry/service/filesystem/process calls, PSScriptAnalyzer rules, parser checks, and fixture-driven tests for DISM, Catalog, HRESULT, WSUS, and Delivery Optimization parsing.
- Improve observability by producing a support bundle: JSON report, transcript/log, WindowsUpdate.log conversion, CBS.log/DISM.log tail, UpdateOrchestrator/WindowsUpdateClient events, and optional redaction.
- Improve policy safety by separating "diagnose managed update source" from "remove policy"; enterprise WSUS/SUP/Intune devices need a confirmation or explicit override before WURepair removes expected policy values.
- Accessibility/i18n: CLI accessibility mostly means noninteractive output, plain text logs, stable exit codes, and no reliance on color; localized endpoint manifests matter more than UI localization for this tool.
- Distribution/upgrade: signed script, PSGallery module wrapper, and GitHub Release ZIP are appropriate; self-update should verify signature and owner/repo before executing any new code.
- Plugin ecosystem, mobile, multi-user, and cloud sync are intentionally not recommended because WURepair is a privileged local repair tool, not a shared service or extensible patch platform.

## Rejected Ideas
- Full Windows Update manager / KB install-block UI from WuMgr or PSWindowsUpdate: useful source, but it changes WURepair from repair into patch management.
- Broad Windows repair suite like Tweaking.com: permission/registry repair is powerful, but too much unrelated blast radius for a focused Windows Update repair tool.
- Background resident agent: commercial patch managers show value here, but WURepair should remain on-demand and auditable.
- Mobile companion app: no credible local repair workflow because operations require elevated Windows access.
- Cloud dashboard / multi-tenant fleet portal: RMM integrations should consume JSON/events; WURepair should not store endpoint state centrally.
- Plugin system: extension hooks around elevated mutation paths would increase security and support burden more than they help a single-purpose tool.
- Automatic driver/firmware repair: adjacent to update failures but belongs to vendor tooling and Windows Update for Business policy, not cache/service repair.

## Sources
OSS competitors:
- https://github.com/wureset-tools/script-wureset
- https://github.com/ManuelGil/Script-Reset-Windows-Update-Tool
- https://github.com/ManuelGil/Reset-Windows-Update-Tool
- https://github.com/mgajda83/PSWindowsUpdate
- https://github.com/taylornrolyat/Repair-WindowsUpdates
- https://github.com/AdmiralEM/windows-update-repair
- https://github.com/iamtraction/fix-windows-update
- https://github.com/ErenElagz/Windows-Update-Fix
- https://github.com/74Thirsty/Windows-Update-Reset

Microsoft/platform:
- https://learn.microsoft.com/en-us/troubleshoot/windows-client/installing-updates-features-roles/common-windows-update-errors
- https://learn.microsoft.com/en-us/troubleshoot/windows-server/installing-updates-features-roles/fix-windows-update-errors
- https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference
- https://learn.microsoft.com/en-us/powershell/module/windowsupdate/get-windowsupdatelog
- https://learn.microsoft.com/en-us/windows/deployment/do/waas-delivery-optimization
- https://learn.microsoft.com/en-us/intune/intune-service/fundamentals/remediations
- https://learn.microsoft.com/en-us/windows/win32/wua_sdk/using-the-windows-update-agent-api
- https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_signing

Tooling/distribution:
- https://github.com/PowerShell/PSScriptAnalyzer
- https://pester.dev/
- https://learn.microsoft.com/en-us/powershell/gallery/how-to/publishing-packages/publishing-a-package
- https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/test-filecatalog

Commercial/adjacent:
- https://www.tweaking.com/content/page/windows_repair_all_in_one.html
- https://www.thewindowsclub.com/fixwin-for-windows-11-and-windows-10
- https://www.action1.com/patch-management/
- https://www.ninjaone.com/patch-management/
- https://www.manageengine.com/patch-management/
- https://www.pdq.com/pdq-deploy/

## Open Questions
- None that block prioritization; implementation should validate behavior on at least one Windows 10/11 VM with Windows PowerShell 5.1 and administrative rights.
