create table little_farm_social.facebook_friendships (
    player_a uuid references little_farm_social.players on delete cascade,
    player_b uuid references little_farm_social.players on delete cascade,
    verified_until timestamptz not null,
    primary key (player_a, player_b),
    check (player_a < player_b)
);

create view little_farm_social.active_friendships as
    select player_a, player_b from little_farm_social.friendships
    union
    select player_a, player_b from little_farm_social.facebook_friendships
    where verified_until > pg_catalog.now();

-- Callable only by the server after it reads a complete list directly from Meta.
create function public.farm_social_sync_facebook(
    p_player uuid, p_facebook_id text, p_friends text[]
)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
    if not exists (
        select 1 from auth.identities
        where user_id = p_player and provider = 'facebook' and provider_id = p_facebook_id
    ) then raise exception 'facebook_identity_mismatch'; end if;

    if not exists (select 1 from little_farm_social.players where id = p_player) then
        return;
    end if;

    -- Serialize snapshots so two players cannot race to replace a mutual link.
    lock table little_farm_social.facebook_friendships in share row exclusive mode;
    delete from little_farm_social.facebook_friendships
    where p_player in (player_a, player_b);

    insert into little_farm_social.facebook_friendships (player_a, player_b, verified_until)
    select distinct least(p_player, p.id), greatest(p_player, p.id),
        pg_catalog.now() + interval '7 days'
    from auth.identities i
    join little_farm_social.players p on p.id = i.user_id
    where i.provider = 'facebook' and i.provider_id = any(p_friends) and p.id <> p_player
    on conflict (player_a, player_b) do update set verified_until = excluded.verified_until;
end;
$$;

revoke all on function public.farm_social_sync_facebook(uuid, text, text[])
    from public, anon, authenticated;
grant execute on function public.farm_social_sync_facebook(uuid, text, text[]) to service_role;

create or replace function public.farm_social_friends()
returns table (id uuid, display_name text)
language sql stable security definer set search_path = ''
as $$
    select p.id, p.display_name
    from little_farm_social.active_friendships f
    join little_farm_social.players p on p.id =
        case when f.player_a = auth.uid() then f.player_b else f.player_a end
    where auth.uid() in (f.player_a, f.player_b)
    order by p.display_name, p.id;
$$;

create or replace function public.farm_social_visit(p_owner uuid)
returns table (id uuid, crop text, remaining integer, ready boolean, claimed boolean)
language plpgsql stable security definer set search_path = ''
as $$
declare
    me uuid := auth.uid();
begin
    if me is null or not exists (
        select 1 from little_farm_social.active_friendships f
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

create or replace function public.farm_social_harvest(p_plot uuid)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
    me uuid := auth.uid();
    plot little_farm_social.plots;
begin
    select p.* into plot from little_farm_social.plots p
    join little_farm_social.active_friendships f
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

