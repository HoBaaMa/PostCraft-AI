CREATE SCHEMA IF NOT EXISTS private;

REVOKE ALL ON SCHEMA private FROM PUBLIC;
REVOKE ALL ON SCHEMA private FROM anon, authenticated;
GRANT USAGE ON SCHEMA private TO postgres;

CREATE TABLE IF NOT EXISTS private.application_admins (
	singleton_id smallint PRIMARY KEY DEFAULT 1,
	user_id uuid NOT NULL UNIQUE REFERENCES auth.users (id) ON DELETE RESTRICT,
	created_at timestamptz NOT NULL DEFAULT now(),
	CONSTRAINT application_admins_singleton_check CHECK (singleton_id = 1)
);

ALTER TABLE private.application_admins ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.application_admins FORCE ROW LEVEL SECURITY;

CREATE POLICY application_admins_postgres_owner_access
	ON private.application_admins
	FOR ALL
	TO postgres
	USING (true)
	WITH CHECK (true);

REVOKE ALL ON TABLE private.application_admins FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE private.application_admins TO postgres;
GRANT INSERT, UPDATE, DELETE ON TABLE private.application_admins TO postgres;

COMMENT ON SCHEMA private IS
	'Non-exposed schema for authorization data accessible only through controlled database functions and owner operations.';

COMMENT ON TABLE private.application_admins IS
	'Singleton allowlist for the configured PostCraft administrator. Provision only through a trusted database-owner session.';

COMMENT ON COLUMN private.application_admins.singleton_id IS
	'Fixed key constrained to 1 so the allowlist can contain at most one administrator.';

COMMENT ON COLUMN private.application_admins.user_id IS
	'Supabase Auth user ID; never provision from an untrusted application request.';