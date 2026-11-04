DO $$
BEGIN
	CREATE SCHEMA extensions;
EXCEPTION
	WHEN duplicate_schema THEN NULL;
END
$$;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
ALTER EXTENSION pgtap SET SCHEMA extensions;

CREATE OR REPLACE FUNCTION public.test_set_admin_claims(admin_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $function$
BEGIN
	PERFORM set_config('request.jwt.claim.sub', admin_user_id::text, true);
	PERFORM set_config('request.jwt.claims', jsonb_build_object(
		'sub', admin_user_id,
		'role', 'authenticated'
	)::text, true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.test_assert_configured_admin(expected boolean, assertion_description text)
RETURNS SETOF text
LANGUAGE sql
STABLE
SET search_path = pg_catalog
AS $function$
	SELECT extensions.is(
		public.is_configured_admin(),
		expected,
		assertion_description
	);
$function$;

CREATE OR REPLACE FUNCTION public.test_set_non_admin_claims(user_id uuid)
RETURNS void
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $function$
BEGIN
	PERFORM set_config('request.jwt.claim.sub', user_id::text, true);
	PERFORM set_config('request.jwt.claims', jsonb_build_object(
		'sub', user_id,
		'role', 'authenticated'
	)::text, true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.test_set_anonymous_claims()
RETURNS void
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $function$
BEGIN
	PERFORM set_config('request.jwt.claim.sub', '', true);
	PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.test_clear_auth_claims()
RETURNS void
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $function$
BEGIN
	PERFORM set_config('request.jwt.claim.sub', '', true);
	PERFORM set_config('request.jwt.claims', '{}', true);
END;
$function$;

REVOKE ALL ON FUNCTION public.test_set_admin_claims(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.test_set_non_admin_claims(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.test_set_anonymous_claims() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.test_clear_auth_claims() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.test_assert_configured_admin(boolean, text) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.test_set_admin_claims(uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.test_set_non_admin_claims(uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.test_set_anonymous_claims() TO postgres;
GRANT EXECUTE ON FUNCTION public.test_clear_auth_claims() TO postgres;
GRANT EXECUTE ON FUNCTION public.test_assert_configured_admin(boolean, text) TO postgres;

SELECT plan(1);
SELECT ok(true, 'shared database test helpers and pgTAP are available');
SELECT * FROM finish();
