-- Fixes from the Supabase security advisor.

-- Pin search_path on the two helpers that had none.
alter function public.edit_price(public.edit_kind) set search_path = public;
alter function public.path_brand(text) set search_path = public;

-- The trigger function is never called directly (triggers don't need EXECUTE).
revoke all on function public.copy_style_to_piece() from public, anon, authenticated;

-- These return a brand id for a piece or shot id; not for visitors who aren't signed in.
-- is_member() and is_staff() stay callable: they only ever answer about the caller.
revoke all on function public.piece_brand(uuid) from public, anon;
revoke all on function public.shot_brand(uuid) from public, anon;
grant execute on function public.piece_brand(uuid) to authenticated;
grant execute on function public.shot_brand(uuid) to authenticated;
