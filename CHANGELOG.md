# Changelog

All notable changes to WURepair will be documented in this file.

## [v2.29.0] - 2026-07-01

- Local validation now prints detected Pester and PSScriptAnalyzer versions and enforces tested minimums with actionable install/update guidance.
- Added `-ListToolVersions` switch to `Invoke-LocalChecks.ps1` for no-network version diagnostics.

## [v2.28.0] - 2026-07-01

- Added `tools\Test-WURepairPackage.ps1` to verify release ZIP checksums, optional file catalogs, Authenticode status, release receipt parity, and extracted module import.
- Build packaging now runs the verifier and records `PackageVerification` in the release receipt.

## [v2.27.0] - 2026-07-01

- JSON reports now include a top-level `RestorePoint` outcome with attempted/skipped/succeeded/failed state, timestamps, failure kind, and error detail.
- Support-bundle `manifest.json` now includes the same restore-point outcome for escalation review.

## [v2.26.0] - 2026-07-01

- Added repair-readiness gating for pending reboot and system-drive BitLocker risk.
- JSON reports now record `RepairReadiness` and `OverrideReadinessBlock` so unattended overrides are auditable.

## [v2.25.0] - 2026-07-01

- Added generated JSON report and support-bundle manifest schema fixture tests.
- Support-bundle `manifest.json` now includes `SchemaVersion`.

## [v2.24.0] - 2026-07-01

- Added public option parity contract tests across script parameters, module wrapper forwarding, CLI parsing, help output, and README option tables.

## [v2.23.0] - 2026-07-01

- Local validation now runs the complete Pester suite by default instead of hard-coded name-filtered batches.
- Added optional Pester coverage output with `Invoke-LocalChecks.ps1 -CoverageOutputPath`.
- Added a static regression test that fails if local checks reintroduce Pester full-name filters.

## [v2.22.0] - 2026-06-29

- Added a versioned endpoint and policy knowledge manifest with Microsoft Learn source URLs.
- Hosts cleanup and diagnostics now use manifest-backed matching for regional Delivery Optimization endpoints.
- Policy repair now consumes manifest-defined removable policy values while preserving managed update-source guardrails.

## [v2.21.0] - 2026-06-29

- Added `WURepair.psd1` and `WURepair.psm1` module metadata/wrappers for phase-oriented invocation.
- Added `tools\Build-WURepairPackage.ps1` to build script and module ZIPs with local checks, SHA256 receipts, optional file catalogs, and optional Authenticode signing.

## [v2.20.0] - 2026-06-29

- Added `-AnalyzeLogs` to export a structured Windows Update log timeline.
- Support bundles now include `logs/WURepair-wulog.json`.
- JSON reports include a compact Windows Update log timeline summary when log analysis runs.

## [v2.19.0] - 2026-06-29

- Added behavior-level validation for CLI option parsing, repair phase selection, DISM source arguments, release version drift, and optional package/remediation artifact parsing.

## [v2.18.0] - 2026-06-29

- Added `-DismSource <path>` for mounted Windows media, `install.wim`, or `install.esd` RestoreHealth repair sources.
- Added `-DismLimitAccess` to prevent Windows Update source fallback during DISM repair.
- JSON reports now include DISM source and `/LimitAccess` option fields.

## [v2.17.0] - 2026-06-28

- Added `-PlainText` deterministic ASCII console output for automation logs and screen readers.
- Plain-text mode suppresses progress rendering and color-only status while preserving log file output.

## [v2.16.0] - 2026-06-28

- Added `-SupportBundle <path>` for redacted diagnostic zip creation.
- Support bundles include WURepair log, JSON report, WindowsUpdate.log, relevant event exports, CBS/DISM tails, and a manifest.
- Added `-NoRedact` to intentionally keep raw usernames, device names, paths, and SIDs in support bundles.
- Catalog package SHA256 validation now falls back to .NET hashing when `Get-FileHash` is unavailable.

## [v2.15.0] - 2026-06-28

- Added managed update-source guardrails for WSUS/SUP/WUfB policy values.
- Full repair now preserves managed source policy by default and requires `-ResetManagedUpdatePolicy` for intentional removal.
- JSON reports include managed-source guardrail fields through WSUS/SUP posture diagnostics.

## [v2.14.0] - 2026-06-28

- Catalog SSU downloads now require SHA256 hashing plus valid Microsoft Authenticode signature before `wusa.exe` runs.
- JSON reports include Catalog package validation records with hash, signature status, and signer metadata.

## [v2.13.0] - 2026-06-28

- Added per-run mutation journal JSON for hosts, registry, policy, and cache changes.
- Added `-RollbackJournal <path>` preview and `-ApplyRollback` restore mode for reversible journal entries.
- JSON reports now include mutation journal path and entry counts.

## [v2.12.0] - 2026-06-28

- Added `-Unattended` mode for RMM/Intune/PDQ/Tanium runs.
- Replaced blocking service cmdlets with timeout-safe `sc.exe` service control.
- Phase results now report `Success`, `Warnings`, or `Errors` with warning/error counts, overall status, and automation exit code.
- Added `Invoke-LocalChecks.ps1` with parser, PSScriptAnalyzer, and Pester validation.

## [v2.11.0] - 2026-06-28

- Added optional `-JsonReport <path>` output for RMM ingestion.
- JSON reports include run metadata, options, phase results, pre/post diagnostics, changed fields, and service deltas.

## [v2.10.0] - 2026-06-28

- Added optional `-RepairServicingStack` Microsoft Update Catalog SSU repair path.
- Catalog repair downloads the newest matching SSU `.msu`, installs it with `wusa.exe /quiet /norestart`, and retries the next match on `0x800f0922`.

## [v2.9.0] - 2026-06-28

- Added `DISM /AnalyzeComponentStore` parsing before component cleanup.
- `StartComponentCleanup /ResetBase` now runs only when cleanup is recommended and reclaimable component-store data is at least 1024 MB.

## [v2.8.0] - 2026-06-28

- Added optional `-StageSSU` / `-StageServicingStack` preflight before DISM.
- Uses Windows Update Agent to find, download, and install the latest applicable Servicing Stack Update before `RestoreHealth`.

## [v2.7.0] - 2026-06-28

- Added `-RepairDelivery` for Delivery Optimization cache and download-mode policy reset.
- Full repair now includes Delivery Optimization cache reset and stale `DODownloadMode` / `DeliveryOptimizationDownloadMode` removal.

## [v2.6.0] - 2026-06-28

- Added `-RepairWaaS` for Update Orchestrator service and USO scheduled task reset.
- Full repair now refreshes USO settings and re-enables disabled `\Microsoft\Windows\UpdateOrchestrator\*` tasks.

## [v2.5.0] - 2026-06-28

- Added WSUS / SUP posture diagnostics for `WUServer`, `WUStatusServer`, target groups, `UseWUServer`, dual-scan, and policy-driven update sources.
- Added DNS resolution summaries and warnings for mismatched or incomplete WSUS policy state.

## [v2.4.0] - 2026-06-28

- Added Microsoft Update Health Tools / Windows Remediation install, service, process, and scheduled task detection.
- Added `uhssvc`, `sedsvc`, `sedlauncher`, remediation process, install path, and version diagnostics.

## [v2.3.0] - 2026-06-28

- Added WaaSMedic service, scheduled task, and recent warning/error event diagnostics.
- Added Delivery Optimization peer cache health, active job count, peer count, cache size, and transfer byte totals to diagnostics.

## [v2.2.0] - 2026-06-28

- Added ranked Windows Update HRESULT diagnostics from `%WINDIR%\WindowsUpdate.log` and converted ETW traces.
- Added Microsoft reference links for recurring Windows Update error codes in the diagnostic pre-check.

## [v2.1.0] - %Y->- (HEAD -> main, tag: v2.1.0, origin/main)

- Added: Add project icon to README
- v2.1.0 - Diagnostic pre-check, selective repair, progress tracking, event log
- Initial commit - WURepair
