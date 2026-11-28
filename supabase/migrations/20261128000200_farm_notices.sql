begin;

create table little_farm_social.notices (
    id bigint generated always as identity primary key,
    owner_id uuid not null references little_farm_social.players on delete cascade,
    visitor_name text not null,
    crop text not null,
    guarded boolean not null,
    created_at timestamptz not null default pg_catalog.clock_timestamp()
);

create index farm_social_notices_owner_created
    on little_farm_social.notices (owner_id, created_at desc, id desc);

-- The trigger runs in the same transaction as the harvest or defense.
-- Retrying an existing claim or block inserts neither a new action nor a notice.
create function little_farm_social.record_farm_notice()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
    insert into little_farm_social.notices (owner_id, visitor_name, crop, guarded)
    select p.owner_id, visitor.display_name, p.crop, tg_table_name = 'guard_blocks'
    from little_farm_social.plots p
    join little_farm_social.players visitor on visitor.id = new.visitor_id
    where p.id = new.plot_id;
    return new;
end;
$$;

revoke all on function little_farm_social.record_farm_notice() from public, anon, authenticated;

create trigger farm_social_notice_harvest
after insert on little_farm_social.harvests
for each row execute function little_farm_social.record_farm_notice();

create trigger farm_social_notice_guard
after insert on little_farm_social.guard_blocks
for each row execute function little_farm_social.record_farm_notice();

create function public.farm_social_notices()
returns table (visitor_name text, crop text, guarded boolean, created_at timestamptz)
language sql stable security definer set search_path = ''
as $$
    select n.visitor_name, n.crop, n.guarded, n.created_at
    from little_farm_social.notices n
    where n.owner_id = auth.uid()
    order by n.created_at desc, n.id desc
    limit 50;
$$;

revoke all on function public.farm_social_notices() from public, anon, authenticated;
grant execute on function public.farm_social_notices() to authenticated;

commit;
