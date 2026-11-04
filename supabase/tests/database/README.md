# Supabase Database Tests (pgTAP)

## Overview

This directory contains database-level tests written in **pgTAP** (PostgreSQL Test Anything Protocol), a Perl-based testing framework for PostgreSQL databases. pgTAP tests run directly inside the database and verify:

- Schema correctness (tables, columns, constraints, indexes, functions)
- Data integrity (unique/foreign-key constraints, check constraints)
- Row-level security (RLS) policies and authorization
- Business logic (stored procedures, functions, triggers)
- Migration idempotency and forward/backward compatibility

## Test Organization

Tests are organized by feature and numbered sequentially for ordering:

```
000_test_helpers.sql           # Reusable pgTAP setup and assertion helpers
010_content_access_test.sql    # Tests for content types, schema versions, items, templates, RLS
020_operation_access_test.sql  # Tests for operations, attempts, activity, RLS
...
```

### Naming Convention

- **3-digit prefix** (e.g., `000`, `010`) — Execution order (pgTAP runs files alphabetically)
- **Descriptive suffix** (e.g., `test_helpers`, `content_access_test`) — Purpose and what is tested
- **Extension**: `.sql` — PostgreSQL/pgTAP SQL

## Test Content Requirements

Each test file must:

1. **Ensure pgTAP is installed**
   ```sql
	  -- 000_test_helpers.sql creates the extensions schema and installs pgTAP there.
   ```

2. **Set up test context**
   - `supabase test db` executes the numbered SQL files in order; `000_test_helpers.sql` installs pgTAP and defines reusable helpers before feature test files run.
   - Create or connect to fixture data
   - Use helper functions for admin/authenticated/anonymous request simulation

3. **Run TAP assertions**
   - Use `SELECT plan(N)` to declare number of assertions
   - Use `SELECT ok()`, `SELECT is()`, `SELECT isnt()` for test logic
   - Use `SELECT throws_ok()` to test permission denials and constraint violations
   - Call `SELECT finish()` at the end

4. **Test RLS with Multiple Contexts**
   - The test connection runs as the database owner. Set JWT claim GUCs with the helper while still owner, then switch database role for the statements being tested.
   - Admin context: `SELECT public.test_set_admin_claims('<admin-uuid>'::uuid); SET LOCAL ROLE authenticated;`
   - Authenticated non-admin context: `SELECT public.test_set_non_admin_claims('<non-admin-uuid>'::uuid); SET LOCAL ROLE authenticated;`
   - Anonymous context: `SELECT public.test_set_anonymous_claims(); SET LOCAL ROLE anon;`
   - After assertions, run `RESET ROLE; SELECT public.test_clear_auth_claims();` before changing context or cleaning up.
   - Only test setup/cleanup runs as the database owner. Never grant test helpers or owner-role membership to application roles.

5. **Clean up after each test**
	  - Restore role and claims: `RESET ROLE; SELECT public.test_clear_auth_claims();`
   - Delete test data (fixtures are ephemeral per test run)

## Running Tests Locally

### Simple Execution

```bash
# Run all database tests with pgTAP output
supabase test db

# Expected output:
# 1..42
# ok 1 - Admin can view content types
# ok 2 - Non-admin cannot view private schemas
# ...
# ok 42 - Generation RLS denies unauthenticated access
```

### Run Specific Test File

```bash
supabase test db tests/database/010_content_access_test.sql
```

### Run with Verbose Output

```bash
supabase test db --verbose
```

### Check Test Results

- **Exit code 0** — All tests passed
- **Exit code non-zero** — At least one test failed (check output for details)

## Test Helper Functions (`000_test_helpers.sql`)

The shared test helpers provide:

### Available Context Helpers

- `test_set_admin_claims(uuid)` — Set admin `sub` and `authenticated` JWT claims; call as the database owner, then issue `SET LOCAL ROLE authenticated` before RLS assertions.
- `test_set_non_admin_claims(uuid)` — Set non-admin `sub` and `authenticated` JWT claims; call as the database owner, then issue `SET LOCAL ROLE authenticated`.
- `test_set_anonymous_claims()` — Set an anonymous JWT role claim; call as the database owner, then issue `SET LOCAL ROLE anon`.
- `test_clear_auth_claims()` — Clear the request JWT claim settings after `RESET ROLE`.
- `test_assert_configured_admin(boolean, text)` — pgTAP assertion for the configured-admin predicate; use during owner-controlled setup/assertion, not as a substitute for a role-switched RLS query.

The helpers only set transaction-local request claim settings; they do not change database roles. This keeps role switching explicit in each test and ensures RLS assertions run with the intended SQL role. The only assertion functions currently available come from pgTAP itself.

### Example RLS Test Transaction

```sql
BEGIN;
SELECT plan(1);
SELECT public.test_set_admin_claims('<admin-uuid>'::uuid);
SET LOCAL ROLE authenticated;
SELECT is((SELECT count(*) FROM public.example_table), 1::bigint, 'configured admin can read the fixture');
RESET ROLE;
SELECT public.test_clear_auth_claims();
SELECT * FROM finish();
ROLLBACK;
```

## Test Data and Fixtures

### Ephemeral Test Data

Each test run:
1. **Starts with a fresh database** (Supabase local stack is reset between runs)
2. **Loads seed data** from `supabase/seed.sql` (if configured)
3. **Runs migrations** in order
4. **Runs tests** against the seeded schema
5. **Discards results** (local stack is reset for next run)

### No Persistent Fixtures

Do not rely on fixtures persisting between test runs. Instead:
- Use `000_test_helpers.sql` to create temporary test users/roles
- Use `INSERT` statements within each test to create test data
- Use `DELETE` to clean up after each test

## RLS Testing Best Practices

### Policy Coverage

For each table with RLS, test:
1. **Admin access** — Can view, insert, update, delete all rows
2. **Authenticated non-admin access** — Gets zero rows (RLS hides all); INSERT/UPDATE/DELETE denied
3. **Anonymous access** — Gets zero rows; cannot access at all

### Sample Test Pattern

```sql
-- Test content_items RLS

-- As admin, can see content items
SELECT set_config('request.jwt.claim.sub', '...admin-user-id...', 'true');
SELECT is((SELECT COUNT(*) FROM content_items), 7, 'Admin can view all content items');

-- As non-admin, cannot see content items
SELECT set_config('request.jwt.claim.sub', '...non-admin-user-id...', 'true');
SELECT is((SELECT COUNT(*) FROM content_items), 0, 'Non-admin cannot view content items');

-- As anonymous, cannot see content items
SELECT set_config('request.jwt.claim.sub', null, 'true');
SELECT is((SELECT COUNT(*) FROM content_items), 0, 'Anonymous cannot view content items');
```

## Troubleshooting

### Test File Not Found

```
Error: supabase test db: no test files found in tests/database
```

**Solution**: Ensure `.sql` files exist in `supabase/tests/database/` and match the pattern.

### pgTAP Not Installed

```
Error: function plan(integer) does not exist
```

**Solution**: Supabase CLI automatically installs pgTAP when starting the local stack. Run `supabase start` first.

### Role Not Found

```
ERROR: role "authenticated_admin_user" does not exist
```

**Solution**: Test helpers must create roles before use. Ensure `000_test_helpers.sql` defines setup functions or create roles in the test file before referencing them.

### RLS Not Enforced

If `SELECT *` returns rows when it should return zero:
1. Verify `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` was run
2. Verify RLS policies exist: `SELECT * FROM pg_policies WHERE tablename = 'content_items'`
3. Verify the session role/user ID is set correctly before the SELECT

## Related Documentation

- **Data Model**: `specs/001-database-data-model/data-model.md` — Tables and policies to test
- **Authentication Contract**: `specs/001-database-data-model/contracts/data-access.md` — Authorized identities and RLS behavior
- **Quickstart**: `specs/001-database-data-model/quickstart.md` — Running `supabase test db` locally
- **pgTAP Documentation**: https://pgtap.org/ — Full pgTAP API reference
- **Supabase Testing Guide**: https://supabase.com/docs/guides/database/local-development/testing — Supabase CLI testing workflow
