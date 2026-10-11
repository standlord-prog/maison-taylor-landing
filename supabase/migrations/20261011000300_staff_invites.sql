-- Emails that become staff on their first sign-in, so nobody has to wait for a manual insert.
-- Add one with: insert into staff_invites (email, name) values ('...', '...');
create table public.staff_invites (
  email text primary key,
  name text not null default ''
);
alter table public.staff_invites enable row level security;  -- no policies: only the SQL editor touches it

create or replace function public.staff_from_invite() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into staff (user_id, name)
  select new.id, i.name from staff_invites i where lower(i.email) = lower(new.email)
  on conflict do nothing;
  return new;
end $$;
revoke all on function public.staff_from_invite() from public, anon, authenticated;

create trigger on_auth_user_staff_invite after insert on auth.users
  for each row execute function public.staff_from_invite();
