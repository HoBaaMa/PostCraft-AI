# PostCraft AI — Master Implementation Plan

## Document Purpose

This document is the project-wide implementation plan and the source from which focused feature specifications will be derived. Implementation should follow the dependency order and delivery waves below. Database, backend, and frontend work may overlap only after their contracts are agreed.

This is a planning document, not authorization to implement every feature in one change. Each wave should be decomposed into a focused specification with explicit acceptance criteria before implementation.

## 1. Product Scope and Outcomes

PostCraft AI is an internal, single-admin platform for creating, validating, enriching, and publishing Android application and game content. It transforms structured app/game information and download URLs into Arabic SEO content, validates download links, provisions clean URLs through an existing Cloudflare Worker, and publishes content to Google Blogger.

PostCraft AI orchestrates and records this work. It does not host APK/game binaries, manage Cloudflare Worker source or deployments, or replace Blogger.

### V1 outcomes

1. The configured administrator can sign in and reach a protected dashboard.
2. The administrator can manage template groups, templates, and immutable/versioned template versions.
3. The administrator can create and edit article inputs, generate and retain multiple content generations, and review output.
4. The administrator can validate a download URL and view current and historical check results.
5. The administrator can provision and reconcile one clean Cloudflare mapping per article.
6. The administrator can connect Blogger, create/reconcile drafts, review them, and explicitly publish.
7. Operations and activity are persisted, observable, and independently retryable.
8. Failures do not invalidate successful previous operations or silently publish content.

### V1 exclusions

Do not build multi-tenancy, complex role hierarchies, APK hosting/upload/storage, Cloudflare Worker creation/deployment/source editing, `slug-mod` links, full CMS functionality, model training, autonomous publishing without an explicit product decision, microservices, distributed brokers, Kubernetes, or a generic enterprise repository/event-sourcing platform.

Monetag configuration and UI are outside V1 and are not implementation tasks in this plan. Any future inclusion requires a separately scoped product decision and specification.

## 2. Technology and Architecture

| Area | Technology / constraint |
|---|---|
| Backend | .NET 10 and ASP.NET Core HTTP API |
| Frontend | Next.js and TypeScript dashboard |
| Data | PostgreSQL through Supabase |
| Authentication | Supabase Auth; backend authorization is authoritative |
| Database secrets | Supabase Vault; application tables store secret references only |
| Object storage | Supabase Storage only where file/object storage is required |
| LLM providers | Gemini and OpenAI behind a common provider abstraction |
| Blogger | Google Blogger API v3 |
| Clean download URLs | Existing Cloudflare Worker; no Worker deployment/source management |
| Hosting | Docker-compatible; Bunny Magic Containers where container hosting is used |
| Repository | One monorepo with clearly separated frontend and backend |

### Architecture principles

- Organize backend code primarily by business feature, not by technical layer. Each vertical slice owns its request models, validation, business logic, endpoint/controller, appropriate persistence queries, and feature tests.
- Keep shared infrastructure outside feature folders. Use interfaces at external boundaries or where they materially improve testability; do not add abstraction layers without a concrete need.
- Keep Gemini, OpenAI, Blogger, Cloudflare Worker, Supabase, and Vault integrations behind dedicated adapters/clients.
- Treat each meaningful external action as a persisted operation with a status, attempt history, idempotency/reconciliation behavior, and independent retry path.
- Keep generated content, template version references, external publication state, operations, link checks, mappings, and activity in persistent storage. In-memory state is execution-only.
- Never return or log API keys, OAuth refresh tokens, Cloudflare credentials, Vault values, Supabase service-role credentials, or sensitive payloads.
- Backend authorization and database Row Level Security (RLS) are both required. The browser is not a security boundary.
- Keep publishing administrator-controlled. Generation success alone never triggers publication unless a future explicit user configuration permits it.

### Repository layout target

```text
postcraft-ai/
├── src/
│   ├── PostCraft.Api/
│   └── PostCraft.Web/
├── tests/
│   ├── PostCraft.Api.Tests/
│   └── PostCraft.Web.Tests/       # when needed
├── database/
│   ├── migrations/
│   └── seeds/
├── docs/
└── specs/                          # focused feature specs/design artifacts
```

Backend feature folders should include `Articles`, `Templates`, `TemplateGroups`, `Generation`, `Links`, `Cloudflare`, `Blogger`, `LlmProviders`, `Operations`, `Activity`, and `Settings`. Shared code belongs in focused `Infrastructure/` and `Common/` areas; avoid a generic repository layer.

## 3. Decisions Required Before Affected Implementation

Resolve these during the corresponding feature specifications/research; do not silently choose an approach in application code.

1. **Admin identity and bootstrap:** Define how the single configured Supabase user is identified, provisioned in development/production, and changed safely. The production policy must not end at `auth.uid() IS NOT NULL`.
2. **Backend database access and RLS context:** Choose one consistent data-access path and document how each request's authenticated admin identity reaches PostgreSQL/RLS. Supabase PostgREST with the user's validated JWT and a carefully designed direct-PostgreSQL claim/role strategy are possible approaches to evaluate. A service-role connection bypassing RLS must not be treated as evidence that RLS is enforcing user authorization. Backend authorization remains mandatory either way.
3. **Migration and seed tooling:** Select the repository's repeatable migration mechanism, local development workflow, and safe production application process. Keep migrations versioned in `database/migrations/` and do not put credentials in them or seeds.
4. **Secret lifecycle:** Define how the trusted backend accesses Supabase Vault, how secret references are represented, and how credentials are rotated/revoked without exposing values to the frontend or logs.
5. **Operation concurrency/recovery:** Define atomic operation claiming, leases/timeouts for abandoned running work, retry limits/backoff, and reconciliation rules for each external integration. Persisted database state is authoritative.
6. **Generation/idempotency semantics:** Define when a user-requested regeneration is a new logical operation versus a retry of an existing operation, and how successful historical generations are preserved.
7. **External integration configuration:** Define callback URLs, allowed origins, deployment environment configuration, and credential provisioning for Google OAuth, Gemini, OpenAI, Cloudflare, and Supabase. Keep environment-specific secrets out of repository files.
8. **Download URL safety:** Define validation and redirect limits, timeouts, allowed schemes, private/local network protections, and response-size behavior. A health check must not download an APK unnecessarily.
9. **Production hosting and observability:** Define deployment environments, health/readiness checks, backups/restore expectations, log retention, and correlation ID propagation before production release.

## 4. Database Workstream

### 4.1 Environment and foundational schema

Create/configure Supabase development and production environments as required. Each environment provides PostgreSQL, Auth, Vault, and Storage where needed. Credentials must be provisioned outside versioned files. Enable `pgcrypto` and use UUID primary keys.

Define the single-admin identity and RLS approach before finalizing policies. Enable RLS on every application table. Policies must grant only the configured PostCraft administrator access. RLS complements, and does not replace, ASP.NET authorization.

### 4.2 Tables and relationships

Create the following application tables, with foreign keys, uniqueness rules, checks, and deletion behavior defined in migrations:

- `template_groups` — named/archivable groups for templates.
- `templates` — template identity and group ownership.
- `template_versions` — versioned instructions, variables, output/SEO requirements, activation state, and immutable historical versions. A template has versions and no more than one active version at a time. Versions become immutable after activation or use.
- `llm_provider_configs` — provider, model, enabled/default state, non-secret provider settings, and Vault secret reference. Never store an API key.
- `articles` — source inputs: app name, version, package name, category, mod details, features, notes, download URL association, template association, and status. Keep user input separate from generated output.
- `article_generations` — append-only successful generation history. Record article, exact template and template version, provider/model, title, HTML, SEO description, features, FAQ, labels, structured content, token usage, and creation time. An article generation MUST reference the exact template version used.
- `download_links` — one primary download link per article in V1, including source URL and current health summary.
- `link_checks` — historical URL check result: status, HTTP status, final URL, latency, timestamps, and error details as appropriate.
- `kv_mappings` — one V1 Cloudflare mapping per article, including slug, key, Worker base URL, namespace reference, and provisioning state. Enforce `kv_key = slug || '-original'`; do not implement `slug-mod`.
- `blogger_publications` — local representation of external Blogger state: blog ID, post ID, status, post URL, title, labels, and errors.
- `operations` — persisted logical actions and attempts, described below.
- `activity_events` — administrator-facing timeline events, distinct from executable operations.

An operation represents work the system executes; an activity event represents something worth showing in the dashboard. For example, a failed `GenerateArticle` operation can create an activity entry stating that generation failed with the selected provider.

### 4.3 Operation records

Support operation types:

- `generate_article`
- `validate_download_link`
- `provision_kv`
- `save_blogger_draft`
- `publish_blogger_post`

Track status, attempt count, idempotency key, correlation ID, external reference, error/category, start time, completion time, and the article association. Define allowed state transitions and retry behavior. A retry continues/reconciles the same logical operation where appropriate and must not repeat successful upstream work unnecessarily.

### 4.4 Indexes and integrity

Add indexes for actual dashboard and worker access patterns, initially including:

- `articles(status)`, `articles(created_at)`
- `templates(group_id)`
- `template_versions(template_id)`
- `article_generations(article_id)`
- `operations(article_id)`, `operations(status)`, `operations(created_at)`
- `link_checks(download_link_id)`
- `activity_events(article_id)`, `activity_events(created_at)`

Add unique constraints for single-active template version, one primary download link/mapping per article, idempotency keys as scoped, and external identifiers where appropriate. Test foreign keys, check constraints, uniqueness, RLS policies, and migration repeatability.

### 4.5 Migration and seed deliverables

Keep migrations and development seed data in version control:

```text
database/
├── migrations/
│   ├── 001_extensions.sql
│   ├── 002_auth.sql
│   ├── 003_templates.sql
│   ├── 004_llm.sql
│   ├── 005_articles.sql
│   ├── 006_links.sql
│   ├── 007_cloudflare.sql
│   ├── 008_blogger.sql
│   ├── 009_operations.sql
│   └── 010_rls.sql
└── seeds/
	└── development.sql
```

The initial development seed should include one template group, two or three templates, multiple template versions, and Gemini/OpenAI configuration metadata. It must contain no secrets. Seed handling must be repeatable and must not overwrite production data.

## 5. Backend Workstream

### 5.1 Foundation and shared infrastructure

Create `src/PostCraft.Api/` on .NET 10/ASP.NET Core. Configure validated configuration, Supabase JWT authentication, administrator authorization, consistent database access, structured logging/correlation IDs, exception handling, health checks, OpenAPI, and serialization/validation. Health endpoints may be public; all business endpoints require administrator authorization.

Use a predictable error response, for example:

```json
{
  "code": "LINK_VALIDATION_FAILED",
  "message": "The download URL returned HTTP 404.",
  "correlationId": "..."
}
```

Do not expose stack traces, secrets, tokens, or sensitive integration payloads in API errors. Define how validation failures, conflicts, not-found results, and integration failures map to HTTP status codes.

Target structure:

```text
PostCraft.Api/
├── Features/
│   ├── Articles/ Templates/ TemplateGroups/ Generation/ Links/
│   ├── Cloudflare/ Blogger/ LlmProviders/ Operations/ Activity/ Settings/
├── Infrastructure/
│   ├── Supabase/ Vault/ Llm/ Cloudflare/ Blogger/ Http/
├── Common/
│   ├── Auth/ Errors/ Validation/ Serialization/
└── Program.cs
```

### 5.2 Authentication, authorization, persistence, and secrets

- Validate Supabase JWTs in ASP.NET Core and enforce the configured admin identity server-side for every business endpoint.
- Keep the backend and RLS identity strategy consistent with the decision in Section 3. Never rely on a frontend-only check or an `auth.uid() IS NOT NULL` policy as the final single-admin policy.
- Implement one consistent database access approach that supports feature queries without a giant generic repository.
- Implement `ISecretProvider` to resolve Vault references for trusted backend integrations. Secret values must never appear in API responses, logs, browser state, or ordinary application tables.
- Restrict CORS/origins and callback endpoints to configured environments; treat frontend input as untrusted.

### 5.3 Operation engine and background processing

Implement the operation infrastructure early, before integrations depend on it. Provide create, claim/start, succeed, fail, and retry/reconcile behavior. Persist before external work. Each feature should define its own operation handler and idempotency/reconciliation semantics.

Create `PostCraftOperationWorker : BackgroundService` for deferred persisted operations. PostgreSQL is the source of truth; memory is temporary execution state. On restart, pending and abandoned running work must be discoverable and safely reclaimed/reconciled. Do not introduce a message broker or distributed workflow engine for V1.

### 5.4 Feature APIs and behavior

All routes below are protected by administrator authorization unless explicitly designated health endpoints.

**Articles**

- `GET /api/articles` — list, filter, and paginate by status/category/date/search as supported.
- `POST /api/articles` — create validated source input.
- `GET /api/articles/{id}` — return article and relevant workflow state.
- `PATCH /api/articles/{id}` — update editable source fields and status with concurrency rules.

**Template groups**

- `GET /api/template-groups`
- `POST /api/template-groups`
- `PATCH /api/template-groups/{id}` — support rename/archive and listing behavior.

**Templates and versions**

- `GET /api/templates`, `POST /api/templates`, `GET /api/templates/{id}`, `PATCH /api/templates/{id}`.
- Add version endpoints/actions for create, edit, duplicate, activate/deactivate, and history, enforcing immutability after activation/use and at most one active version.
- Build variable resolution for variables such as `{{app_name}}`, `{{version}}`, `{{package_name}}`, `{{category}}`, `{{mod_details}}`, `{{features}}`, `{{notes}}`, and `{{download_url}}`.

**LLM provider and prompt system**

- Define `ILlmProvider`, provider registry, and independently mockable Gemini/OpenAI adapters.
- Registry resolves provider name, configuration, Vault secret reference, and client without exposing secret values.
- Build a testable prompt component accepting article input, exact template version, and variables and returning a resolved prompt.

**Article generation**

- `POST /api/articles/{id}/generate` creates an operation, loads the article and selected immutable template version, resolves variables/provider, calls the model, parses structured output, validates it, persists a successful `article_generations` record, and completes the operation.
- Validate title, SEO description, HTML body, features, FAQ, labels, and required structured fields.
- Malformed or invalid model output fails the operation; it must not persist as a partially successful generation. Preserve every successful generation as history.
- Record provider, model, template version, token usage, and correlation/operation identifiers.

**Download-link validation**

- `POST /api/articles/{id}/link-check` creates a persisted operation and history record.
- Implement `ILinkHealthChecker`: make a bounded HTTP request, follow permitted redirects, evaluate the final status, and record status/HTTP status/final URL/latency/time/error. Treat HTTP 200 as success for the initial requirement; define redirect and non-200 behavior in the link feature spec.
- Do not download APK content unnecessarily. Enforce the URL safety requirements defined in Section 3.

**Cloudflare Worker**

- Implement `ICloudflareWorkerClient` to create/update and, where needed, check the `slug-original` mapping through the existing Worker integration.
- Enforce the mapping key rule and one mapping per article. Make provisioning idempotent and reconciliable. Do not create or deploy a Worker or edit Worker source.

**Blogger and OAuth**

- Implement `IBloggerClient` for OAuth-backed API access, draft creation, update/reconciliation, publishing, and retrieval.
- Provide an administrator connection flow: initiate Google OAuth, handle callback, store refresh token in Vault, and persist only non-secret integration metadata. Never return a refresh token after connection.
- Implement `IBloggerArticleRenderer` accepting generation, download link, Cloudflare mapping, and site settings and producing Blogger HTML.
- `POST /api/articles/{id}/blogger/draft` creates/reconciles an idempotent Blogger draft.
- `POST /api/articles/{id}/blogger/publish` requires an eligible generated/draft state and explicit administrator action. Keep draft and published state visible locally.

**Operations, retry, activity, and settings**

- `POST /api/operations/{id}/retry` retries a failed operation as the same logical action with a new attempt; do not regenerate successful upstream operations unnecessarily.
- `GET /api/activity` supports article, event-type, and date filters.
- Settings model non-secret Blogger Blog ID, Cloudflare Worker base URL/namespace reference, and site configuration. LLM provider configuration stores metadata and Vault references. Do not include Monetag settings in V1.
- Every important operation emits structured activity/log events with article ID, operation ID, correlation ID, integration, duration, result, and error category where appropriate.

### 5.5 Backend testing

Create unit and integration coverage for administrator authorization, article CRUD, template/group/version rules, variable resolution, prompt building, provider selection, generation parser/validation, link checker, Cloudflare client, Blogger/OAuth boundaries, operation state machine, idempotency, retry/reconciliation, and activity recording. Mock external systems in deterministic tests. Integration tests must use isolated database/configuration and must not require real credentials by default.

## 6. Frontend Workstream

### 6.1 Foundation and authentication

Create `src/PostCraft.Web/` with Next.js and TypeScript. Set up routes/layouts, session handling, centralized API client, loading/error handling, and accessible forms. Implement `/login` with Supabase Auth; the frontend obtains a session and calls the backend, but never decides final authorization. The backend is authoritative.

### 6.2 Application shell and navigation

Build sidebar, top bar, main content, notifications, and user/session state. Navigation: Dashboard, Articles, Templates, Links, Activity, and Settings. Do not add business operations that bypass the .NET API.

### 6.3 Dashboard and article workflow

- Dashboard: Draft/Ready/Published article counts; Running/Failed/Recent operations; Healthy/Unhealthy links; recent activity.
- `/articles`: search, status/category filters, date sorting, pagination, and create action.
- `/articles/new`: app name, version, package name, category, mod details, features, notes, download URL, and template. Validate in the UI for usability and again in the backend for correctness/security.
- `/articles/{id}`: article information, generated content, SEO, download link, Cloudflare state, Blogger state, operations, and activity.
- Generation controls: Generate/Regenerate; display provider, model, exact template version, generation state, and last error. Never expose API keys, Vault IDs, or secret configuration values.
- Generated-content view: title, SEO description, HTML, features, FAQ, and labels. Clearly distinguish generated, edited, and published state if manual editing is introduced.

### 6.4 Links, Cloudflare, and Blogger UI

- `/links`: Healthy/Unhealthy/Unknown status, article, URL, HTTP status, final URL, latency, last checked; actions Check, Retry, and Update URL.
- Article Cloudflare section: original/clean URL, KV status, provision/re-provision action, and explicit `slug-original` mapping display.
- Article Blogger section: Blogger status, draft/published URL, Create Draft, Publish, and Retry. Publishing requires clear confirmation.

### 6.5 Operations, templates, and settings UI

- Operations view/timeline: operation type, status, attempts, duration, error, timestamps, retry controls; clearly show success/failure/not-run states.
- `/templates` and `/templates/{id}`: groups, templates, versions, create/edit/duplicate/activate/deactivate, and supported template variables.
- `/settings/llm`: provider, model, enabled/default state; allow secret entry but never display a stored key after submission.
- `/settings`: General, Blogger, Cloudflare, and LLM configuration. Keep non-secret configuration distinct from secret management. Monetag is excluded from V1.
- `/activity`: chronological filterable activity, including operation outcomes.

### 6.6 Frontend API, state, and tests

Centralize calls under `lib/api/` (for example `articlesApi`, `templatesApi`, `operationsApi`, `linksApi`, `bloggerApi`, and `settingsApi`); do not scatter raw `fetch(...)` calls through components. Use simple server-state management initially. Every mutation needs loading, success, failure, and retry behavior; display backend correlation IDs where useful. Test authentication, forms, loading/error states, operation display, and critical workflows.

## 7. Workstream Contracts

```text
Supabase PostgreSQL schema
		  ↓
	 .NET REST API
		  ↓
	 Next.js dashboard
```

- Database migrations define persistent data constraints and RLS.
- The backend owns business logic, authorization, orchestration, validation, secrets access, and external integrations.
- The frontend uses Supabase Auth for sign-in/session and the .NET API for business actions. It does not bypass the backend for application data mutations or external services.
- OpenAPI is the source for API request/response contracts. Agree on status enums, operation states, pagination/filter conventions, error envelopes, correlation IDs, and date/time formats before frontend integration.
- Schema/API changes must be coordinated and documented; do not silently change shared contracts.

## 8. Dependency Graph and Delivery Waves

### Dependency order

```text
Database design and auth/RLS decision
  ↓
Migrations and admin identity
  ↓
Backend authentication/authorization and data access
  ↓
Persisted operation engine
  ↓
Template groups and versioned templates
  ↓
Article CRUD and LLM provider/prompt foundation
  ↓
Generation and history
  ↓
Link validation
  ↓
Cloudflare mapping
  ↓
Blogger OAuth/client/renderer/draft/publish
  ↓
Frontend feature integration
  ↓
End-to-end, failure/retry, security, production readiness
```

The frontend foundation can begin alongside backend foundation after authentication, API, and contract decisions are established. Do not start feature UI against unstable contracts.

### Wave 1 — Foundation

- **Database:** environments, extensions, admin identity, core schema design, RLS strategy.
- **Backend:** .NET 10 project, JWT authentication/authorization, database connection strategy, common errors, logging, health checks, OpenAPI.
- **Frontend:** Next.js foundation, Supabase Auth, protected application shell.
- **Exit outcome:** configured administrator can sign in and reach an authenticated empty dashboard; authorization is independently enforced by the backend.

### Wave 2 — Templates

- **Database:** template groups, templates, template versions, constraints, seed data.
- **Backend:** group/template APIs, version lifecycle, variable resolution.
- **Frontend:** groups, template list/editor, version management.
- **Exit outcome:** administrator can create/manage templates and immutable versions; only one version is active per template.

### Wave 3 — LLM and Articles

- **Database:** articles, generations, LLM configuration metadata.
- **Backend:** article CRUD, provider abstraction, Gemini/OpenAI, prompt builder, operation-backed generation, output validation/history.
- **Frontend:** article creation/details, generate/regenerate, generated content and state.
- **Exit outcome:** administrator can create an article and generate/review Arabic content with exact template/provider history.

### Wave 4 — Link Health

- **Database:** download links and link-check history.
- **Backend:** safe URL checker, redirect/status handling, operation/retry behavior.
- **Frontend:** article link status, health center, check/retry/update URL.
- **Exit outcome:** administrator can validate a download URL and inspect current and historical checks.

### Wave 5 — Cloudflare

- **Database:** KV mappings and non-secret Worker configuration.
- **Backend:** Worker client, `slug-original`, idempotent provisioning/reconciliation.
- **Frontend:** clean URL/status and provision/re-provision controls.
- **Exit outcome:** administrator can provision and view one clean mapping per article through the existing Worker.

### Wave 6 — Blogger

- **Database:** publication state and integration metadata.
- **Backend:** OAuth, Vault-backed refresh-token handling, Blogger client, HTML renderer, draft, publish, reconciliation.
- **Frontend:** connect Blogger, create/view draft, explicitly publish, retry.
- **Exit outcome:** administrator can create a Blogger draft, review it, and publish it explicitly.

### Wave 7 — Operations Center

- **Database:** final operation indexes and activity event coverage.
- **Backend:** operation engine hardening, retry/reconciliation, recovery, activity logging.
- **Frontend:** operation timeline, retry controls, activity center, failure dashboard.
- **Exit outcome:** persisted work is diagnosable and recoverable without repeating successful upstream operations unnecessarily.

### Wave 8 — End-to-End and Production Hardening

Run the full workflow, intentionally fail LLM, link validation, Cloudflare, and Blogger actions, and verify independent retry/reconciliation. Complete security review, migration/backup/recovery checks, deployment configuration, and production readiness.

- **Exit outcome:** the complete administrator-controlled workflow is tested, observable, secure, and deployable.

## 9. Cross-Cutting Requirements

### Security

Never expose LLM API keys, Cloudflare tokens, Blogger refresh tokens, Supabase service-role credentials, or Vault secrets. Enforce backend authorization and RLS, protect OAuth callbacks and secrets, validate input at all trust boundaries, and verify no secrets occur in logs, browser bundles, API responses, seeds, or repository configuration.

### Idempotency and failure handling

Every external mutation must have an idempotency/reconciliation strategy, especially generation, Cloudflare provisioning, Blogger draft creation, and Blogger publishing. Failures must be explicit and recoverable; never catch an exception and return success. Define which failures are retryable, how attempt history is recorded, and how external state is reconciled.

### Observability

Propagate article ID, operation ID, and correlation ID through API requests, background work, integration logs, and activity records. Include integration, duration, result, and error category where appropriate. Exclude secrets and sensitive request payloads.

### Validation and persistence

Validate at the frontend for user experience, backend for business/security correctness, and database for integrity. Persist all important workflow and history state. A UI state or in-memory worker state is never the system of record.

## 10. Testing Strategy and Release Gates

### Database

Test migration application, constraints, foreign keys, unique rules, indexes for key access patterns, RLS for the configured admin and unauthenticated/non-admin identities, and seed repeatability. Test with the selected backend data-access path so policy behavior is demonstrated end to end.

### Backend

- **Unit:** template resolver/version rules, prompt builder, provider selection, generation parser/validation, link checker, operation state machine, idempotency, retry/reconciliation.
- **Integration:** API-to-database, JWT authentication/authorization, API-to-operations, migration compatibility, persisted activity.
- **External clients:** deterministic mocks/fakes for Gemini, OpenAI, Cloudflare, Blogger, and Vault boundary behavior. Maintain a smaller optional real-integration suite using dedicated credentials where practical; never require production credentials for normal builds/tests.

### Frontend

Test sign-in/session handling, protected routes, forms and validation, loading/success/error/retry behavior, operation status display, secret non-disclosure, and critical workflow components.

### End-to-end

Primary workflow:

```text
Login → Create Article → Generate → Validate Link → Provision KV
	  → Create Blogger Draft → Review → Explicitly Publish
```

Failure scenarios include generation failure followed by generation retry, Blogger failure followed by Blogger-only retry, and isolated link/Cloudflare failure and recovery. Verify a failed step does not undo prior successes or repeat unrelated successful operations.

### Release gates

Do not advance a wave until its acceptance outcome is met, its migrations/contracts are documented, relevant tests pass, authorization/secrets behavior is verified, and unresolved decisions needed by the next wave are closed. Production deployment additionally requires reviewed configuration/secrets, health checks, migration/rollback strategy, recovery procedures, and successful end-to-end/failure testing.

## 11. Final Implementation Order

1. Repository foundation.
2. Supabase project/database environments.
3. Database migrations.
4. Admin authorization and RLS.
5. .NET 10 foundation.
6. Supabase JWT authentication.
7. Operation infrastructure.
8. Template Groups.
9. Templates.
10. Template Versions.
11. Article CRUD.
12. LLM provider abstraction.
13. Gemini provider.
14. OpenAI provider.
15. Prompt Builder.
16. Article Generation.
17. Generation history.
18. Download Link model.
19. Link Health Checker.
20. Link Health Center API.
21. Cloudflare Worker integration.
22. KV idempotency.
23. Blogger configuration.
24. Blogger OAuth.
25. Blogger client.
26. Blogger HTML renderer.
27. Blogger Draft.
28. Blogger Publish.
29. Operation retry/reconciliation.
30. Activity system.
31. Next.js authentication.
32. Next.js application shell.
33. Dashboard.
34. Article UI.
35. Template UI.
36. Generation UI.
37. Link Health UI.
38. Cloudflare UI.
39. Blogger UI.
40. Operations UI.
41. Settings UI.
42. End-to-end workflow.
43. Failure/retry testing.
44. Security hardening.
45. Production deployment.

This sequence is a dependency guide, not a requirement to postpone all frontend foundation until item 31; Wave 1 allows frontend foundation to proceed alongside backend foundation once contracts are established.

## 12. Focused Specifications to Derive

Create focused specifications from this master plan rather than one giant feature specification:

1. **SPEC-01 — Database Setup:** environments, migrations, schema, admin identity, RLS, seeds.
2. **SPEC-02 — Backend Foundation:** API foundation, auth/authorization, data access, errors, logging, health, OpenAPI.
3. **SPEC-03 — Template Management:** groups, templates, versions, lifecycle, variables.
4. **SPEC-04 — Article and LLM Generation:** article CRUD, providers, prompts, generation operations, validation/history.
5. **SPEC-05 — Link Health:** URL safety, health checks, history, operations/retries, health API/UI.
6. **SPEC-06 — Cloudflare Integration:** existing Worker client, mappings, idempotency, configuration, UI.
7. **SPEC-07 — Blogger Integration:** OAuth/Vault, client, rendering, drafts, publishing, reconciliation.
8. **SPEC-08 — Operations and Reliability:** operation engine hardening, retries, recovery, activity, observability.
9. **SPEC-09 — Frontend Dashboard:** auth, shell, dashboard, article/template/settings/operations/activity interfaces and API client.
10. **SPEC-10 — E2E and Production Hardening:** full workflow, failure scenarios, security review, deployment readiness.

Each focused specification must read the project constitution, resolve relevant open decisions, define API/database contracts and acceptance criteria, and identify tests before implementation begins.
