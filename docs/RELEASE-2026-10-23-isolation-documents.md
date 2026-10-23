# Application isolation, route calculator and trip documents

Production: https://respectlogistic.onrender.com
Branch: respectlogistic/customers

The fleet, counterparty and trip modules used shared crm_* tables with only owner-based RLS. Both CRMs use the same account; owner filtering did not separate applications. Legacy records were not deleted or adopted. New records use explicit app_scope=respectlogistic. Same-origin API requests now use security-invoker, owner-and-app filtered views with checked writes. Trip RPCs reject legacy reference IDs; payroll/maintenance use separate scoped RPCs. Existing unscoped operations remain available to the original CRM. Plate uniqueness includes owner and app.

The salary calculator accepts an editable saved driver rate. Route distance is read-only and comes from the selected driver's trip and its current customer object. Existing payroll snapshots and completed payments are preserved.

Each trip has a document row. Private PDF/JPG/PNG/WEBP uploads are limited to 10 MB. No documents is red; uploaded files await explicit full-set confirmation; green requires a completed trip and confirmed documents. Changing the trip's customer/object/vehicle/driver/date/service invalidates confirmation. Uploads are authenticated and scoped to owner/trip. A confirmed, completed trip creates an export queue entry.

Google Drive export hierarchy: customer → object → service → trip date → plate. Upload retry reuses folders and skips files by immutable source document ID. Failures preserve the original private files and appear in the queue. The application attempts pending exports while the trips page is open. There is no background worker when the page is closed; pending entries remain durable for the next visit.

Automatic Drive export requires server-side OAuth configuration, separate from the ChatGPT Drive connector:
- GOOGLE_DRIVE_CLIENT_ID
- GOOGLE_DRIVE_CLIENT_SECRET
- GOOGLE_DRIVE_REFRESH_TOKEN (offline Drive access)
- GOOGLE_DRIVE_TRIPS_ROOT_FOLDER_ID

Store credentials in Render environment settings, never in source, browser storage, public variables, chat messages or logs. Share/authorize the chosen target folder with the account represented by the OAuth refresh token. Without configuration the site reports awaiting_connection, never a successful archive. No real customer documents existed at inspection, so no live document archive was possible in this release.

Apply database migrations in order: app_isolation.sql, trip_documents.sql, app_boundary_guards.sql. Earlier migrations remain prerequisites. Do not rerun already applied DDL indiscriminately. The isolation SQL references database functions installed by earlier releases.

Validation: customer/fleet/trips pure logic, proxy scope/write restrictions, Drive hierarchy/retry/failure behavior; authenticated SQL integration with rolled-back customer/trip/fleet/storage metadata fixtures. It covers same-owner foreign driver/trip exclusion, forbidden assignment, CRUD, optimistic locking, atomic protected deletion, payroll, document confirmation, queue claim locking, pending connection and invalidation. Render build verifies Next.js/TypeScript. Browser access limitations are reported separately; a successful build/live deploy is not a visual UI test.

Restoration: use the exact release source ZIP and its accompanying status record. Restore the matching source commit on the deployment branch. Keep app isolation migrations in place; restoring an old proxy would re-expose legacy shared data. Never restore unscoped reads as an application rollback.
