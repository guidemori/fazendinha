-- Keep social state private. Only the RPC functions below may change it.
create schema little_farm_social;

create table little_farm_social.players (
    id uuid primary key references auth.users(id) on delete cascade,
    friend_code uuid not null unique default gen_random_uuid(),
    display_name text not null check (char_length(display_name) between 1 and 32)
);

create table little_farm_social.friendships (
    player_a uuid references little_farm_social.players on delete cascade,
    player_b uuid references little_farm_social.players on delete cascade,
    primary key (player_a, player_b),
    check (player_a < player_b)
);

create table little_farm_social.plots (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references little_farm_social.players on delete cascade,
    crop text not null,
    ready_at timestamptz not null,
    remaining integer not null check (remaining >= 0)
);

-- Each row both grants one unit to the visitor and records their claim.
create table little_farm_social.harvests (
    visitor_id uuid references little_farm_social.players on delete cascade,
    -- Retain the granted unit if the owner deletes their farm.
    plot_id uuid not null,
    crop text not null,
    primary key (visitor_id, plot_id)
);

create function public.farm_social_profile(p_name text default null)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
    me uuid := auth.uid();
    profile little_farm_social.players;
begin
    if me is null then raise exception 'authentication_required'; end if;
    if p_name is not null then
        insert into little_farm_social.players (id, display_name)
        values (me, pg_catalog.btrim(p_name))
        on conflict (id) do update set display_name = excluded.display_name
        where players.display_name <> excluded.display_name;
    end if;

    select * into profile from little_farm_social.players where id = me for update;
    if not found then return null; end if;

    -- One server-managed test plot, separate from the offline save.
    if not exists (select 1 from little_farm_social.plots where owner_id = me) then
        insert into little_farm_social.plots (owner_id, crop, ready_at, remaining)
        values (me, 'cenoura', pg_catalog.now(), 1);
    end if;

    return pg_catalog.jsonb_build_object(
        'friendCode', profile.friend_code, 'displayName', profile.display_name
    );
end;
$$;

create function public.farm_social_add_friend(p_code uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
    me uuid := auth.uid();
    friend uuid;
begin
    if not exists (select 1 from little_farm_social.players where id = me) then
        raise exception 'profile_required';
    end if;
    select id into friend from little_farm_social.players where friend_code = p_code;
    if friend is null or friend = me then raise exception 'invalid_friend_code'; end if;

    insert into little_farm_social.friendships (player_a, player_b)
    values (least(me, friend), greatest(me, friend))
    on conflict do nothing;
end;
$$;

create function public.farm_social_friends()
returns table (id uuid, display_name text)
language sql stable security definer set search_path = ''
as $$
    select p.id, p.display_name
    from little_farm_social.friendships f
    join little_farm_social.players p on p.id =
        case when f.player_a = auth.uid() then f.player_b else f.player_a end
    where auth.uid() in (f.player_a, f.player_b)
    order by p.display_name, p.id;
$$;

create function public.farm_social_visit(p_owner uuid)
returns table (id uuid, crop text, remaining integer, ready boolean, claimed boolean)
language plpgsql stable security definer set search_path = ''
as $$
declare
    me uuid := auth.uid();
begin
    if me is null or not exists (
        select 1 from little_farm_social.friendships f
        where f.player_a = least(me, p_owner) and f.player_b = greatest(me, p_owner)
    ) then raise exception 'friendship_required'; end if;

    return query
    select p.id, p.crop, p.remaining, p.ready_at <= pg_catalog.now(), h.plot_id is not null
    from little_farm_social.plots p
    left join little_farm_social.harvests h on h.plot_id = p.id and h.visitor_id = me
    where p.owner_id = p_owner
    order by p.id;
end;
$$;

create function public.farm_social_harvest(p_plot uuid)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
    me uuid := auth.uid();
    plot little_farm_social.plots;
begin
    select p.* into plot from little_farm_social.plots p
    join little_farm_social.friendships f
        on f.player_a = least(me, p.owner_id) and f.player_b = greatest(me, p.owner_id)
    where p.id = p_plot and me is not null
    for update of p;
    if not found then raise exception 'friendship_required'; end if;

    -- Retrying a successful request returns the original result.
    if exists (select 1 from little_farm_social.harvests where plot_id = p_plot and visitor_id = me) then
        return plot.crop;
    end if;
    if plot.ready_at > pg_catalog.now() or plot.remaining < 1 then
        raise exception 'crop_unavailable';
    end if;

    update little_farm_social.plots set remaining = remaining - 1 where id = p_plot;
    insert into little_farm_social.harvests (visitor_id, plot_id, crop)
    values (me, p_plot, plot.crop);
    return plot.crop;
end;
$$;

create function public.farm_social_inventory()
returns table (crop text, quantity bigint)
language sql stable security definer set search_path = ''
as $$
    select h.crop, pg_catalog.count(*)
    from little_farm_social.harvests h where h.visitor_id = auth.uid()
    group by h.crop
    order by h.crop;
$$;

revoke all on schema little_farm_social from public, anon, authenticated;
revoke all on function public.farm_social_profile(text), public.farm_social_add_friend(uuid),
    public.farm_social_friends(), public.farm_social_visit(uuid), public.farm_social_harvest(uuid),
    public.farm_social_inventory() from public, anon, authenticated;
grant execute on function public.farm_social_profile(text), public.farm_social_add_friend(uuid),
    public.farm_social_friends(), public.farm_social_visit(uuid), public.farm_social_harvest(uuid),
    public.farm_social_inventory() to authenticated;
