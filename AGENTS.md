# CRM development instructions

Production: https://respectlogistic.onrender.com
Render service: srv-dbci9j1srm7s73b5ejvg
Deploy branch: respectlogistic/customers (not main).
Supabase project: yoqejkedmksmvbqagqru.

Preserve the customer section design: pale sage background, white rounded panels, charcoal sidebar, lime accents. Verify mobile layout, wrapping of long names and native modal behavior.

Own fleet uses crm_drivers and crm_vehicles with carrier_id IS NULL and explicit app_scope=respectlogistic; vehicles must also have is_subcontractor_vehicle=false. Never read shared crm_* tables without the application boundary. Same-origin requests must use rl_crm_* checked security-invoker views. Legacy rows with no application provenance belong to the other CRM and must not be adopted or deleted. Original payroll RPCs remain for the other app; this site uses rl_crm_* payroll/maintenance variants.
Salary uses ONE route leg. Bonus adds to base pay. Company tax adds to company expense and never reduces driver salary. Fine deductions reduce driver payout only after a saved allocation. Use existing payroll RPCs; do not create a second ledger.

All customer service prices INCLUDE VAT22 (user confirmed). Accounting uses respectlogistic_accounting_* tables and validated owner RPCs; draft/issued snapshots, per-object registry counters, active trip/document-kind uniqueness. Invoice issuance never completes trips; UPD/registry issuance explicitly confirms completion, preserving separate driver-document confirmation. Issued snapshots lock trip financial/context fields. Advance credits transfer available paid advances to invoice debt without generating revenue or cash twice. Preserve document history, cancelled numbers and signed documents. Templates: https://drive.google.com/drive/folders/1MMOBU-vRFWiJyxVqG90tV5Ya6uExUmgG . Base UPD printout is a review form until the company's template is supplied; no EDI/XML capability is claimed.

After authorized changes: test calculations and database ownership/relationships, deploy to Render, wait for the exact final deploy to become live, then verify actual page/API behavior when access is available. State verification limitations accurately.

The user requested a development archive in Google Drive: "crm в рендер".
Root folder: 1h-QC-M-5ip6Fmhu8pCU24TlTVCToPFty
Sources/versions: 1h6-j8qu8twdw9WCXOfyqDIAx27WFGC6H
Mockups: 16tutq3XlL531dvVdLIbXI7DMqcfAYmKt
Development log: 1G6upW2vSl6IS0X30sZkejZWjJQ1s2f2j
For each completed release, upload source archive, SQL migrations, release notes, validation results, exact commit and restore instructions. Exclude secrets, .env files, tokens, node_modules and customer database records. This is a source archive, not an automatic database backup. Preserve these folder IDs and report upload failures honestly.
