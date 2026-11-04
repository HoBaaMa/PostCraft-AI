CREATE OR REPLACE FUNCTION public.is_configured_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, auth, private
AS $function$
	SELECT auth.uid() IS NOT NULL
	   AND EXISTS (
			SELECT 1
			FROM private.application_admins AS application_admin
			WHERE application_admin.singleton_id = 1
			  AND application_admin.user_id = auth.uid()
	   );
$function$;

ALTER FUNCTION public.is_configured_admin() OWNER TO postgres;

REVOKE ALL ON FUNCTION public.is_configured_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_configured_admin() TO authenticated, postgres;

COMMENT ON FUNCTION public.is_configured_admin() IS
	'Returns whether auth.uid() matches the single configured administrator; does not expose allowlist contents.';