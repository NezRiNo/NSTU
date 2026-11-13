-- Обновление 11: главный администратор.
-- Только главный администратор видит список администраторов, добавляет и убирает их.
-- ВЫПОЛНИТЕ СРАЗУ: пока этот файл не выполнен, второй администратор может убрать вас из списка.
-- Supabase -> SQL Editor -> New query -> вставить -> Run. Требуются update-5 и update-10.

-- 1. Метка «главный» (не больше одного)
alter table public.admins add column if not exists is_owner boolean not null default false;

update public.admins set is_owner = true
where user_id = (select id from auth.users where email = 'hlebsmaslom13@gmail.com');

create unique index if not exists admins_one_owner on public.admins ((true)) where is_owner;

create or replace function public.is_owner()
returns boolean
language sql stable security definer
set search_path = ''
as $$ select exists (select 1 from public.admins where user_id = (select auth.uid()) and is_owner) $$;

revoke all on function public.is_owner() from public, anon;
grant execute on function public.is_owner() to authenticated;

-- 2. Управление администраторами: только главный
drop function if exists public.list_admins();
create function public.list_admins()
returns table(uid uuid, mail text, is_main boolean)
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if not public.is_owner() then raise exception 'forbidden'; end if;
  return query
    select a.user_id, u.email::text, a.is_owner
    from public.admins a join auth.users u on u.id = a.user_id
    order by a.is_owner desc, u.email;
end $$;

create or replace function public.add_admin(p_nick text)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare v_email text; v_id uuid;
begin
  if not public.is_owner() then raise exception 'forbidden'; end if;
  v_email := lower(trim(p_nick));
  if position('@' in v_email) = 0 then v_email := v_email || '@example.com'; end if;
  select id into v_id from auth.users where email = v_email;
  if v_id is null then raise exception 'user not found'; end if;
  insert into public.admins (user_id) values (v_id) on conflict do nothing;
end $$;

create or replace function public.remove_admin(p_user_id uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
begin
  if not public.is_owner() then raise exception 'forbidden'; end if;
  if p_user_id = (select auth.uid()) then raise exception 'cannot remove yourself'; end if;
  if exists (select 1 from public.admins where user_id = p_user_id and is_owner) then
    raise exception 'cannot remove owner';
  end if;
  delete from public.admins where user_id = p_user_id;
end $$;

-- 3. Сброс пароля: пароль администратора может поставить только главный,
--    пароль главного не может поставить никто (он меняет его сам в кабинете)
create or replace function public.admin_set_password(p_nick text, p_password text)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare v_email text; v_id uuid;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  if length(p_password) < 8 then raise exception 'password too short'; end if;
  v_email := lower(trim(p_nick));
  if position('@' in v_email) = 0 then v_email := v_email || '@example.com'; end if;
  select id into v_id from auth.users where email = v_email;
  if v_id is null then raise exception 'user not found'; end if;
  if exists (select 1 from public.admins where user_id = v_id and is_owner) then
    raise exception 'cannot reset owner password';
  end if;
  if exists (select 1 from public.admins where user_id = v_id) and not public.is_owner() then
    raise exception 'forbidden target';
  end if;
  update auth.users
     set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')),
         updated_at = now()
   where id = v_id;
end $$;

revoke all on function public.list_admins() from public, anon;
revoke all on function public.add_admin(text) from public, anon;
revoke all on function public.remove_admin(uuid) from public, anon;
revoke all on function public.admin_set_password(text, text) from public, anon;
grant execute on function public.list_admins() to authenticated;
grant execute on function public.add_admin(text) to authenticated;
grant execute on function public.remove_admin(uuid) to authenticated;
grant execute on function public.admin_set_password(text, text) to authenticated;

-- Проверка: должна вернуться одна строка с is_owner = true (вы).
select user_id, is_owner from public.admins where is_owner;
