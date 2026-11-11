create schema extensions; create schema vault; create schema auth; create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as 'select nullif(current_setting(''request.jwt.claim.sub'', true), '''')::uuid';
create function auth.role() returns text language sql stable as 'select current_setting(''request.jwt.claim.role'', true)';
create function auth.jwt() returns jsonb language sql stable as 'select null::jsonb';
create schema storage; create table storage.buckets(id text primary key, name text, public boolean, file_size_limit bigint, allowed_mime_types text[]);
create table storage.objects(id uuid); create publication supabase_realtime;
grant usage on schema public to anon, authenticated, service_role;
