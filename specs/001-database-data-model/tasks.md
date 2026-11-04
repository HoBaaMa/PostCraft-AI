# Tasks: Database and Data Model

**Input**: Design documents from `specs/001-database-data-model/` (`plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/data-access.md`, `quickstart.md`)

**Prerequisites**: Design documents are complete. This feature implements Supabase database assets and only the minimum ASP.NET Core authentication/data-access boundary required to preserve the verified administrator identity. General business endpoints and frontend work belong to later specifications.

**Tests**: Include pgTAP and ASP.NET Core integration-test tasks because the specification defines database acceptance criteria and backend identity-propagation behavior that must be verified.

**Organization**: Tasks are grouped by the three user stories in `spec.md`, ordered by priority. Database migrations, seed data, and pgTAP tests use the Supabase CLI layout; backend identity propagation uses the .NET API and integration-test projects.

## Phase 1: Setup

**Purpose**: Establish the local Supabase database workflow.

- [ ] T001 Initialize Supabase CLI project configuration in `supabase/config.toml` for local PostgreSQL, Auth, Vault, database tests, and seed loading
- [ ] T002 [P] Create the .NET 10 ASP.NET Core API project and xUnit integration-test project in `src/PostCraft.Api/PostCraft.Api.csproj` and `tests/PostCraft.IntegrationTests/PostCraft.IntegrationTests.csproj`
- [ ] T003 [P] Create the database migration directory and document its ordered SQL naming convention in `supabase/migrations/README.md`
- [ ] T004 [P] Create the database test directory and document local pgTAP invocation in `supabase/tests/database/README.md`

## Phase 2: Foundational

**Purpose**: Create shared authorization and test prerequisites that block all application data stories.

- [X] T005 Create the protected `private` schema, singleton `private.application_admins` allowlist with a unique `auth.users` reference, and trusted provisioning boundary in `supabase/migrations/20261004000100_admin_identity.sql`
- [X] T006 Implement the boolean `is_configured_admin()` database predicate with a pinned safe `search_path`, schema-qualified references, restricted function privileges, and no direct allowlist access in `supabase/migrations/20261004000200_admin_predicate.sql`
- [X] T007 [P] Add reusable pgTAP setup/assertion helpers for administrator, authenticated non-admin, and anonymous request contexts in `supabase/tests/database/000_test_helpers.sql`
- [X] T008 Document and enforce the migration/bootstrap versus ordinary user-request credential boundary in `supabase/migrations/README.md`

**Checkpoint**: Shared Supabase configuration, admin predicate, and RLS-test context are ready before story tables are added.

## Phase 3: User Story 1 - Preserve Generic Content (Priority: P1)

**Goal**: Persist generic content types, versioned input schemas, content items, and optional selected template references without imposing Android-specific fields.

**Independent Test**: Seed or create representative items for Android app reviews, game reviews, product reviews, tutorials, news, comparisons, and custom content; retrieve each item's type, pinned schema version, source JSON, lifecycle status, and optional template references. Confirm unsupported statuses, mismatched schema/type references, duplicate scoped identifiers, and non-admin access are rejected.

### Tests for User Story 1

- [ ] T009 [P] [US1] Add ASP.NET Core integration tests proving configured-admin JWT validation, matching admin-RPC/data-request bearer identity, denial for missing/invalid/non-admin tokens, RLS-denial behavior, and zero privileged fallback in `tests/PostCraft.IntegrationTests/Authentication/SupabaseIdentityPropagationTests.cs`
- [ ] T010 [P] [US1] Add pgTAP tests for generic content round trips, schema-version pinning, lifecycle statuses, template references, same-type schema FKs, and admin/non-admin/anonymous RLS in `supabase/tests/database/010_content_access_test.sql`

### Implementation for User Story 1

- [ ] T011 [US1] Configure JWT bearer validation for trusted Supabase issuer, audience, signature, lifetime, and verified subject in `src/PostCraft.Api/Program.cs` and `src/PostCraft.Api/Features/Authentication/SupabaseJwtOptions.cs`
- [ ] T012 [US1] Implement a request-scoped Supabase data client that forwards the original verified user bearer token without shared mutable authorization headers in `src/PostCraft.Api/Infrastructure/Supabase/SupabaseDataClient.cs`
- [ ] T013 [US1] Implement the configured-admin authorization handler that invokes `is_configured_admin()` using the original verified user token and fails closed in `src/PostCraft.Api/Features/Authentication/ConfiguredAdminAuthorizationHandler.cs`

- [ ] T014 [US1] Create `content_types`, `content_type_schema_versions`, and `content_items` with UUID keys, JSONB source values, required FKs, unique `(content_type_id, version_number)`, and statuses exactly `Draft`, `In Review`, `Ready`, `Published`, or `Archived` in `supabase/migrations/20261004001000_content_core.sql`
- [ ] T015 [US1] Add a composite FK ensuring every content item schema version belongs to the same content type in `supabase/migrations/20261004001000_content_core.sql`
- [ ] T016 [US1] Create `template_groups`, `templates`, and immutable numbered `template_versions`, then add nullable selected template references to content items with matching-template/version integrity, unique scoped keys, and positive version numbers in `supabase/migrations/20261004001000_content_core.sql`
- [ ] T017 [US1] Add content-list, type/status, and schema-version lookup indexes in `supabase/migrations/20261004001000_content_core.sql`
- [ ] T018 [US1] Enable RLS and add admin-only `USING`/`WITH CHECK` policies for content types, schema versions, content items, template groups, templates, and template versions in `supabase/migrations/20261004001100_content_core_rls.sql`
- [ ] T019 [US1] Seed the seven initial generic content types—Android app review, game review, product review, tutorial, news, comparison, and custom content—with representative schema-version rows, a template group/template/version, and no secret values in `supabase/seed.sql`

**Checkpoint**: User Story 1 is independently verifiable by `supabase test db` and retains schema-version/source-value identity across later schema additions.

## Phase 4: User Story 2 - Preserve Template and Generation History (Priority: P1)

**Goal**: Persist provider metadata and each generated output with the exact template version and provider/model used, without modifying earlier generation history or storing credentials in ordinary tables.

**Independent Test**: Create successive template versions and multiple generations for one item; verify each generation references its exact immutable version and provider/model snapshot, earlier outputs remain unchanged, only non-secret provider settings/Vault references are stored, and admin-only RLS applies.

### Tests for User Story 2

- [ ] T020 [P] [US2] Add pgTAP tests for unique positive template versions, prevention of in-place edits to referenced versions, and at-most-one enabled default provider in `supabase/tests/database/020_generation_history_test.sql`
- [ ] T021 [P] [US2] Add pgTAP tests for exact generation-to-template-version/provider references, output retention, scoped FK/unique constraints, and admin/non-admin/anonymous RLS in `supabase/tests/database/021_generation_access_test.sql`

### Implementation for User Story 2

- [ ] T022 [US2] Add append-only enforcement for template versions once referenced and preserve prior version rows when a template is revised in `supabase/migrations/20261004002000_generation_history.sql`
- [ ] T023 [US2] Create `llm_provider_configs` with provider/model identifiers, enabled/default flags, non-secret JSONB settings, Vault secret reference only, and a partial unique index allowing at most one enabled default in `supabase/migrations/20261004002000_generation_history.sql`
- [ ] T024 [US2] Create append-only `content_generations` with content-item FK, exact template-version FK, provider-config reference, provider/model snapshots, generated output, usage metadata, and creation time in `supabase/migrations/20261004002000_generation_history.sql`
- [ ] T025 [US2] Add generation-by-content/time and provider lookup indexes in `supabase/migrations/20261004002000_generation_history.sql`
- [ ] T026 [US2] Enable RLS and add admin-only `USING`/`WITH CHECK` policies for provider configurations and content generations in `supabase/migrations/20261004002100_generation_rls.sql`
- [ ] T027 [US2] Add representative Gemini and OpenAI provider/model metadata with no actual credential values in `supabase/seed.sql`

**Checkpoint**: User Story 2 is independently verifiable from persisted generation relationships and retained version/output records.

## Phase 5: User Story 3 - Inspect Recoverable Workflow State (Priority: P2)

**Goal**: Persist independent operations and attempts, activity timelines, optional validation/clean-link records, and Blogger state; archive content without deleting local history.

**Independent Test**: For one content item, record successful and failed operation attempts, multiple link checks, activity events, and optional external records; verify status families remain distinct, all history is queryable, archive preserves it, and unauthorized identities receive no application-owned rows.

### Tests for User Story 3

- [ ] T028 [P] [US3] Add pgTAP tests for content creation/update and integration operation types, nullable pre-item creation linkage, required successful-create linkage, attempt history, idempotency uniqueness, and separate external states in `supabase/tests/database/030_operations_history_test.sql`
- [ ] T029 [P] [US3] Add pgTAP tests for link-health and Blogger-publication status sets, optional capability enforcement, repeated link checks, archive-history retention, and admin/non-admin/anonymous RLS in `supabase/tests/database/031_external_state_archive_test.sql`

### Implementation for User Story 3

- [ ] T030 [US3] Create `operations` and `operation_attempts` with types `ContentCreation`, `ContentUpdate`, `Generation`, `LinkValidation`, `CleanLinkProvisioning`, `BloggerDraftCreation`, `BloggerPublishing`; statuses exactly `Pending`, `Running`, `Succeeded`, `Failed`, `Cancelled`; permit null content-item reference only for pre-item `ContentCreation`, require it after successful creation and for every other type; persist idempotency/correlation IDs, timestamps, scoped uniqueness, and attempt details in `supabase/migrations/20261004003000_operations_external_state.sql`
- [ ] T031 [US3] Create `activity_events` as non-executable timeline records with content FK, event type, timestamp, actor/correlation metadata, and safe JSONB details in `supabase/migrations/20261004003000_operations_external_state.sql`
- [ ] T032 [US3] Create optional `download_links` and `link_checks` with current/history separation, statuses exactly `Unknown`, `Healthy`, `Unhealthy`, and at most one primary download link per content item in `supabase/migrations/20261004003000_operations_external_state.sql`
- [ ] T033 [US3] Create optional `clean_link_mappings` with external Worker reference only and `blogger_publications` with statuses exactly `Draft`, `Published`, `Unknown`; keep external state separate from operation errors in `supabase/migrations/20261004003000_operations_external_state.sql`
- [ ] T034 [US3] Enforce each optional record's content-type capability in database write logic and add operation, activity, link-check, and external-state lookup indexes in `supabase/migrations/20261004003000_operations_external_state.sql`
- [ ] T035 [US3] Enable RLS and add admin-only `USING`/`WITH CHECK` policies for operations, attempts, activity, download links, link checks, clean-link mappings, and Blogger publications in `supabase/migrations/20261004003100_workflow_rls.sql`
- [ ] T036 [US3] Add pgTAP fixtures and assertions proving archiving updates content status without deleting generations, operations/attempts, link checks, mappings, Blogger records, or activity in `supabase/tests/database/032_archive_retention_test.sql`

**Checkpoint**: User Story 3 is independently verifiable by querying a complete retained workflow history after archival.

## Phase 6: Polish and Cross-Cutting Validation

**Purpose**: Verify a clean database lifecycle, all acceptance criteria, security boundaries, and documented local workflow.

- [ ] T037 [P] Add a migration-level pgTAP audit that every application-owned table has RLS enabled and an allowlist-backed admin policy in `supabase/tests/database/090_rls_coverage_test.sql`
- [ ] T038 Run `supabase db reset` from a clean local state and verify ordered migrations plus `supabase/seed.sql` initialize successfully; record any required fixes in the corresponding SQL files
- [ ] T039 Run `supabase test db` and resolve failures in the owning migration or test files
- [ ] T040 Verify no seed or migration contains actual provider credentials, OAuth tokens, Cloudflare credentials, or Supabase service-role secrets; record the result in `specs/001-database-data-model/quickstart.md`
- [ ] T041 Validate database constraints and the complete ASP.NET Core identity-propagation workflow in `specs/001-database-data-model/quickstart.md`, including configured admin, non-admin, malformed/expired tokens, anonymous access, and no privileged fallback

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1: Setup** establishes the Supabase CLI project, .NET API/test projects, JWT validation, and user-token data client.
- **Phase 2: Foundational** depends on Setup and blocks data stories because the admin predicate and request authorization handler are shared prerequisites.
- **Phase 3: US1** depends on the foundational admin predicate and backend identity boundary; it creates content/schema/template-reference tables used by later stories.
- **Phase 4: US2** depends on US1's content, template, and template-version tables.
- **Phase 5: US3** depends on US1's content records and US2's generation tables for complete history/archive validation.
- **Phase 6: Polish** depends on all selected stories being complete.

### User Story Dependencies

- **US1 (P1)**: Starts after Phase 2; no dependency on another user story.
- **US2 (P1)**: Starts after US1 because its generations reference content items and template versions.
- **US3 (P2)**: Starts after US1 and US2 to validate history and archival across all persisted entities.

### Parallel Opportunities

- In Setup, T001 and T002 can start independently; T003 depends on T002 and T004 depends on T003. T005 and T006 can proceed independently after T001 creates the Supabase directory.
- In Foundational, T006 depends on T005 establishing the private schema/table; T007 test helpers can be prepared independently after the local test layout exists; T008 documents the migration boundary.
- Within US1, T009 and T010 can be prepared in parallel after their respective project/test foundations exist. Then implement T011 (JWT validation), T012 (token-forwarding data client), and T013 (admin check) in dependency order before any ordinary data request. Migration tasks T014–T016 share one ordered migration file and should be coordinated sequentially; T017 follows those schema definitions. T019 seeds the types/templates in one file after schema creation.
- Within US2, T020 and T021 can be prepared in parallel. T022–T024 share a migration file and should be coordinated sequentially; T025 and T026 follow table creation. T027 edits the shared seed file and runs after US1 seed tasks.
- Within US3, T028 and T029 can be prepared in parallel. T030–T033 share a migration file and should be coordinated sequentially; T034 follows table definitions. T035 follows all workflow tables. T036 requires completed history tables to run.
- After the foundational phase, story work is intentionally sequential by dependency (US1 → US2 → US3), not independently parallel across all stories.

## Parallel Example: User Story 1

```text
Task T009: Prepare backend identity-propagation integration coverage in tests/PostCraft.IntegrationTests/Authentication/SupabaseIdentityPropagationTests.cs
Task T010: Prepare content/schema/status and RLS pgTAP coverage in supabase/tests/database/010_content_access_test.sql
```

## Implementation Strategy

### MVP First

1. Complete Phase 1 and Phase 2, including the tested authentication/data-access boundary and database admin predicate.
2. Complete Phase 3 (US1) as the MVP: generic content types, pinned schema versions, source records, selected template references, and enforceable backend identity propagation.
3. Run the backend identity tests and US1 pgTAP checks; confirm non-admin/anonymous denial and zero privileged fallback before expanding the schema.
4. Complete US2 to add reproducible generation and provider history.
5. Complete US3 to add recoverable operations, optional external state, and archive-retained history.
6. Complete Phase 6 clean-reset, full test, and secret-safety validation.

### Incremental Delivery

Deliver in dependency order: the authenticated identity boundary and content persistence first, generation history second, then operational/external history. Each phase leaves the preceding data schema usable and adds its own migration and acceptance coverage.

## Notes

- Every task follows `- [ ] T### [P?] [US#?] Description with file path`.
- `[P]` is used only when a task can proceed independently without editing a concurrently modified file or depending on unfinished work.
- Story labels map directly to `US1`, `US2`, and `US3` in `spec.md`.
- Database and backend tests are included because the feature defines persistence acceptance scenarios and requires the backend identity/RLS boundary to be exercised.
- All lifecycle/status values and version/idempotency uniqueness constraints are explicit in the relevant task descriptions.
- No general business API endpoints, UI, LLM execution, OAuth flows, or live Blogger/Worker actions are included; only the minimum ASP.NET Core JWT/admin authorization and Supabase data-client boundary is in scope.
