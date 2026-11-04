<!--
Sync Impact Report
Version change: unversioned scaffold -> 1.0.0 (first complete constitution)
Modified principles: none
Added principles: Feature-First Architecture; Pragmatic Vertical Slice Architecture; External Systems Have Explicit Boundaries; Operations Are Independent and Retryable; Persist Important State; Secrets Never Reach the Frontend; Provider-Agnostic LLM Architecture; Templates Are Versioned; Human-Controlled Publishing; Idempotency; Observability; No Unnecessary Infrastructure
Added sections: Purpose; Technology Baseline; System Boundaries; Security; AI Coding Rules; V1 Non-Goals; Definition of Done
Removed sections: none
Follow-up TODO: Confirm the original ratification date and replace TODO(RATIFICATION_DATE).
-->
# PostCraft AI Constitution

## Core Principles

### 1. Feature-First Architecture
Backend code MUST be organized primarily around business capabilities rather than technical layers. Preferred feature folders are `Articles`, `Templates`, `TemplateGroups`, `Generation`, `Links`, `Cloudflare`, `Blogger`, `LlmProviders`, `Operations`, `Activity`, and `Settings` under `Features/`. Shared infrastructure MUST remain outside feature folders.

### 2. Pragmatic Vertical Slice Architecture
PostCraft AI MUST use pragmatic Vertical Slice Architecture. Each feature owns its request models, validation, business logic, endpoint or controller, appropriate persistence queries, and feature-specific tests. The project MUST NOT introduce a large enterprise Clean Architecture structure without a real requirement. Interfaces MUST be used where they protect external boundaries or substantially improve testability, such as `ILlmProvider`, `IBloggerClient`, `ICloudflareWorkerClient`, `ILinkHealthChecker`, and `ISecretProvider`.

### 3. External Systems Have Explicit Boundaries
Integrations with Gemini, OpenAI, Google Blogger, the Cloudflare Worker, Supabase, and Supabase Vault MUST be isolated behind dedicated adapters or clients. Business features SHOULD depend on abstractions where practical so integration details do not spread through business logic.

### 4. Operations Are Independent and Retryable
The publishing workflow MUST consist of independent operations: draft, generate article, validate download link, provision Cloudflare KV, save Blogger draft, and publish Blogger post. Each operation MUST have its own status and history, fail independently, and be independently retryable; operations SHOULD be idempotent where possible. A failure MUST NOT invalidate successful previous operations, and the complete workflow MUST NOT be treated as one database transaction.

### 5. Persist Important State
Important workflow state MUST be persisted and MUST NOT rely on in-memory, browser, temporary process, or undocumented external state. Operations, generated content, link checks, KV mappings, Blogger publication state, and activity events MUST be persisted.

### 6. Secrets Never Reach the Frontend
API keys, OAuth refresh tokens, Cloudflare credentials, LLM keys, and similar secrets MUST never be returned to the Next.js application, stored as plaintext in ordinary application tables, logged, or included in API responses. Sensitive credentials MUST be stored using Supabase Vault; application tables may store only references to Vault secrets.

### 7. Provider-Agnostic LLM Architecture
Content generation MUST use a common provider abstraction and MUST support Gemini and OpenAI. Article-generation business logic MUST NOT be tightly coupled to one LLM vendor, so another provider can be added without rewriting that logic.

### 8. Templates Are Versioned
Templates are business data and MUST support groups, versions, activation and deactivation, duplication, editing, variables, system and user instructions, output requirements, and SEO requirements. Every article-generation operation MUST record the exact template version used. Later template changes MUST NOT alter historical generated content.

### 9. Human-Controlled Publishing
Publishing state MUST remain visible to the administrator. The administrator MUST be able to generate, review, validate, create Blogger drafts, publish, and retry failures. Generation success MUST NOT silently publish content unless the user explicitly configured that behavior.

### 10. Idempotency
Mutating operations MUST use idempotency when duplicate external actions could cause problems, including Cloudflare KV provisioning, Blogger draft creation and publishing, article generation, and link checks. Retries SHOULD continue or reconcile the existing operation rather than create unintended duplicates.

### 11. Observability
Important operations MUST produce structured logs or events with appropriate identifiers, such as article ID, operation ID, correlation ID, integration name, duration, result, and error category. Secrets, API keys, tokens, and sensitive request payloads MUST NOT be logged.

### 12. No Unnecessary Infrastructure
Version 1 MUST avoid microservices, Kafka, RabbitMQ, Kubernetes, distributed workflow engines, separate content services, and separate LLM services unless an actual requirement emerges. A .NET `BackgroundService` is sufficient for deferred V1 operations.

## Purpose, Technology Baseline, System Boundaries, and Security

### Purpose
PostCraft AI is an internal, single-admin automation platform for creating, validating, enriching, and publishing Android application and game content. It transforms structured app and game information and download URLs into Arabic SEO content, validates download links, provisions clean Cloudflare Worker links, and publishes content to Google Blogger. PostCraft AI is an orchestration and content-management system; it does not host APK files, manage Cloudflare Worker deployments, or replace Google Blogger.

### Technology Baseline
The project MUST use .NET 10 for the backend, ASP.NET Core for the HTTP API, Next.js for the frontend dashboard, and PostgreSQL through Supabase for application data. Authentication MUST use Supabase Auth. Supabase Vault MUST store sensitive integration secrets, and Supabase Storage MUST be used where file or object storage is required. Blogger integration MUST use Google Blogger API v3. Clean download URLs MUST use an existing Cloudflare Worker. Gemini and OpenAI MUST be supported LLM providers. Deployment MUST be Docker-compatible, using Bunny Magic Containers where container hosting is used.

The repository is a monolith. Frontend and backend code MAY reside in the same repository but MUST remain clearly separated.

### System Boundaries
PostCraft AI owns articles, generated content, templates, template groups and versions, LLM configuration metadata, link validation state, Cloudflare KV mappings, Blogger publication records, operations, and activity history.

PostCraft AI does NOT own APK or game binaries, Cloudflare Worker source code or deployment, Blogger infrastructure, Google accounts, LLM infrastructure, or external download hosting.

### Security
Only the configured PostCraft administrator may access the application. Authorization MUST be enforced server-side; the frontend MUST NOT be considered a security boundary. Database Row Level Security MUST be enabled on application tables.

## AI Coding Rules, V1 Non-Goals, and Definition of Done

### AI Coding Rules
AI coding agents MUST read this constitution before implementation, follow existing project patterns before introducing new ones, avoid unnecessary abstractions, avoid silently changing API or database contracts, add tests when behavior changes, never hardcode credentials, keep integrations mockable, preserve idempotency, keep changes focused, and prefer small vertical slices over large rewrites.

Requirements take precedence in this order: Constitution, PRD, Architecture, Tasks, then implementation details.

### V1 Non-Goals
The following are outside V1: multi-tenancy; complex role management; APK hosting or upload infrastructure; Cloudflare Worker creation, deployment, or source editing; `slug-mod` links; full CMS functionality; model training; autonomous publishing without administrator control; microservice architecture; and distributed message brokers.

### Definition of Done
A feature is complete only when it follows the architecture, enforces authorization, includes needed validation, isolates external integrations, handles failures, defines retry behavior, persists important state, protects secrets, tests important behavior, and does not unintentionally break an existing workflow.

## Governance
This constitution takes precedence over the PRD, architecture, tasks, and implementation details. An amendment MUST document its rationale and impact, be reviewed and approved by the configured PostCraft administrator, update the version and last-amended date, and be checked against affected project guidance. The ratification date records original adoption and MUST NOT change during later amendments.

Constitution versions MUST follow semantic versioning. A MAJOR increment denotes backward-incompatible governance or principle removals or redefinitions; a MINOR increment denotes a new principle or section or materially expanded guidance; a PATCH increment denotes clarification, wording, typo, or other non-semantic refinement.

Compliance MUST be reviewed during feature planning and implementation review. Reviews MUST check applicable principles, security and secret-handling rules, integration boundaries, persistence and retry behavior, tests, and Definition of Done requirements. Any justified exception MUST be documented and approved by the configured administrator.

**Version**: 1.0.0 | **Ratified**: 2026-10-02: original adoption date unknown | **Last Amended**: 2026-10-02
