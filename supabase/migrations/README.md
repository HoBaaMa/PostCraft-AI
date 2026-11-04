# Supabase Database Migrations

## Overview

This directory contains all SQL migrations for the PostCraft database schema. Migrations are version-controlled and applied in strict order to ensure database consistency across environments (local development, staging, production).

## Migration Naming Convention

Migrations follow the **strict ordering convention** used by Supabase CLI:

```
YYYYMMDDHHMMSS_descriptive_name.sql
├─ Timestamp: UTC timestamp when migration was created (YYYYMMDDHHMMSS)
└─ Name: hyphen-separated, lowercase descriptive purpose
```

### Timestamp Precision

- **Date**: 8 digits (YYYYMMDD) — sortable by calendar date
- **Time**: 6 digits (HHMMSS) — ensures ordering within a single day
- **UTC timezone**: All timestamps in UTC for consistency across deployments

### Naming Examples

```
20261004000100_admin_identity.sql        # 2026-10-04 00:01:00 UTC
20261004000200_admin_predicate.sql       # 2026-10-04 00:02:00 UTC
20261004001000_content_core.sql          # 2026-10-04 01:00:00 UTC
20261004001100_content_core_rls.sql      # 2026-10-04 01:01:00 UTC
```

## Migration Content Requirements

Each migration must:

1. **Be idempotent** — Safe to run multiple times without error
   - Use `CREATE TABLE IF NOT EXISTS`
   - Use `CREATE OR REPLACE FUNCTION` for functions
   - Reference immutable OIDs for type/function safety across schema versions

2. **Preserve data integrity** — No data loss during schema evolution
   - Use `ALTER TABLE` to add columns, constraints, or indexes
   - Document any breaking changes in comments at the top of the file
   - Use `CREATE OR REPLACE VIEW` for safe view evolution (if no structural changes)

3. **Fail visibly** — Clear error messages if constraints are violated
   - Add inline SQL comments explaining the purpose of each constraint
   - Use `CONSTRAINT` names that describe the rule, e.g., `content_items_fk_type`

4. **Include schema and comments**
   - All objects must belong to named schemas (`private`, `public`, or custom)
   - Add `COMMENT ON` statements to explain intent of tables, columns, indexes

## Ordering and Dependency

Migrations are applied in **strict chronological order by filename**. Later migrations may depend on schema created by earlier ones, but:

- **Forward dependencies are forbidden** — A migration never assumes schema from a later file
- **Sequence is immutable** — Once a migration runs in production, its timestamp cannot change
- **Safe rollback requires new forward migrations** — Never modify or delete a migration; instead, write a new migration to reverse it

## Migration Execution Workflow

### Local Development

```bash
# Start the local Supabase stack (includes PostgreSQL)
supabase start

# When you've created a new migration file:
supabase db reset          # Runs all migrations from scratch, then loads seed data
supabase db push           # Pushes local migrations to remote (caution: production)
```

### Testing

```bash
# Run database tests (pgTAP)
supabase test db

# Run specific test file
supabase test db supabase/tests/database/010_content_access_test.sql
```

### Production Promotion

1. **Create migration locally** in this directory
2. **Test locally** with `supabase db reset` and `supabase test db`
3. **Push to upstream branch** for review
4. **Promote to staging** via `supabase db push` to staging environment
5. **Verify staging tests** run successfully
6. **Manually promote to production** (all-hands decision)

## Bootstrap vs. Ordinary User Requests

### Migration and Bootstrap Boundary

Schema migrations run through the Supabase CLI's trusted database connection. This connection can create and own schemas, tables, functions, and policies, and is not an application credential. Never put the database password, access token, or service-role key in migrations, seed data, source control, or ordinary runtime configuration.

Provision the one administrator only after the corresponding user exists in Supabase Auth:

1. Apply migrations using the trusted operator workflow (`supabase db reset` locally or a reviewed `supabase db push` to the intended linked project).
2. Obtain the administrator's UUID from the trusted Supabase Auth user-management interface or an approved operator-only query. Do not accept it from an application request or commit it to the repository.
3. Open an owner-controlled SQL session to the intended database, using a secret manager or an interactive prompt for connection credentials. Do not paste credentials into command history or commit them.
4. Open `psql` in interactive mode, prompt for the Auth UUID, then run the following statement. Do not interpolate unchecked text into SQL:

   ```sql
	 \\prompt 'Administrator Auth user UUID: ' ADMIN_USER_ID

   INSERT INTO private.application_admins (singleton_id, user_id)
   VALUES (1, :'ADMIN_USER_ID'::uuid)
   ON CONFLICT (singleton_id)
   DO UPDATE SET user_id = EXCLUDED.user_id;
   ```

5. Verify the row through the same trusted owner session. Treat changing or removing this identity as an audited administrative action. Never add an administrator UUID to `supabase/seed.sql`.

The allowlist table has RLS enabled and forced, and direct access is revoked from `anon`, `authenticated`, and `service_role`. The `postgres` database owner is the trusted provisioning boundary; `public.is_configured_admin()` is the only application-facing check and returns a boolean, not the allowlist row.

### Ordinary User Requests

After bootstrap, ordinary API requests must carry the verified user's Supabase JWT. The API obtains the subject from the validated token and forwards that same token to the admin predicate and normal Supabase requests. PostgreSQL `auth.uid()` resolves the authenticated subject used by the predicate and RLS. Application requests must not use database-owner or service-role credentials, including as an error fallback, and must not set identity claims from unverified request data.

### Enforcement Boundaries

- **This README** documents separate trusted bootstrap/provisioning and ordinary request flows.
- **Supabase JWT auth** verifies the caller's identity.
- **Database row-level security (RLS)** enforces authorization using `auth.uid()` and the configured-admin predicate.
- **Backend authorization handler** checks `is_configured_admin()` with the original verified user token.

See also: `specs/001-database-data-model/contracts/data-access.md` for the full backend data-access contract.

## Related Documentation

- **Data Model**: `specs/001-database-data-model/data-model.md` — Tables, columns, constraints, and relationships
- **Authentication Contract**: `specs/001-database-data-model/contracts/data-access.md` — JWT validation, RLS, backend identity propagation
- **Quickstart**: `specs/001-database-data-model/quickstart.md` — Local setup and validation commands
- **Test Helpers**: `supabase/tests/database/000_test_helpers.sql` — pgTAP utilities for testing RLS and authorization
