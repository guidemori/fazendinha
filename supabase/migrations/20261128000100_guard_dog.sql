begin;

alter table little_farm_social.players
    add column guard_until timestamptz,
    add column guard_fed_until timestamptz,
    add column guard_defenses integer not null default 0 check (guard_defenses between 0 and 3);

create table little_farm_social.guard_blocks (
    owner_id uuid not null references little_farm_social.players on delete cascade,
    plot_id uuid not null references little_farm_social.plots on delete cascade,
    visitor_id uuid not null references little_farm_social.players on delete cascade,
    primary key (owner_id, plot_id, visitor_id)
);

create index farm_social_harvests_plot on little_farm_social.harvests (plot_id);

create function public.farm_social_guard(p_feed boolean, p_renew boolean)
returns timestamptz
language plpgsql security definer set search_path = ''
as $$
declare
    me uuid := auth.uid();
    fed_until timestamptz;
begin
    if me is null then raise exception 'authentication_required'; end if;
    if p_feed then
        update little_farm_social.players
        set guard_fed_until = pg_catalog.clock_timestamp() + interval '12 hours'
        where id = me returning guard_fed_until into fed_until;
    else
        update little_farm_social.players
        set guard_until = pg_catalog.clock_timestamp() + interval '24 hours',
            guard_defenses = 3
        where id = me and (p_renew or guard_until is null)
        returning guard_fed_until into fed_until;
        if found then
            delete from little_farm_social.guard_blocks where owner_id = me;
        end if;
    end if;
    return fed_until;
end;
$$;

revoke all on function public.farm_social_guard(boolean, boolean) from public, anon, authenticated;
grant execute on function public.farm_social_guard(boolean, boolean) to authenticated;

drop function public.farm_social_visit(uuid);
create function public.farm_social_visit(p_owner uuid)
returns table (id uuid, crop text, remaining integer, protected integer, ready boolean, claimed boolean)
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
    select p.id, p.crop, p.remaining - reserve.quantity, reserve.quantity,
        p.ready_at <= pg_catalog.now(), h.plot_id is not null
    from little_farm_social.plots p
    join little_farm_social.players owner on owner.id = p.owner_id
    cross join lateral (
        select case when owner.guard_until > pg_catalog.now()
            and owner.guard_fed_until > pg_catalog.now()
            and owner.guard_defenses > 0
            then least(p.remaining, (p.remaining + claimed.total + 1) / 2)
            else 0 end as quantity
        from (
            select count(*)::integer as total from little_farm_social.harvests all_claims
            where all_claims.plot_id = p.id
        ) claimed
    ) reserve
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
    owner little_farm_social.players;
    already_collected integer;
    checked_at timestamptz;
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

    -- Serialize the farm-wide defense quota even for visits to different plots.
    select * into owner from little_farm_social.players
    where id = plot.owner_id for update;
    checked_at := pg_catalog.clock_timestamp();

    if owner.guard_until > checked_at and owner.guard_fed_until > checked_at then
        if exists (select 1 from little_farm_social.guard_blocks blocked
            where blocked.owner_id = owner.id and blocked.plot_id = p_plot
                and blocked.visitor_id = me) then
            return 'guard_dog_protected';
        end if;
        if owner.guard_defenses > 0 then
            select count(*)::integer into already_collected
            from little_farm_social.harvests where plot_id = p_plot;
            if plot.remaining <= (plot.remaining + already_collected + 1) / 2 then
                insert into little_farm_social.guard_blocks (owner_id, plot_id, visitor_id)
                values (owner.id, p_plot, me);
                update little_farm_social.players
                set guard_defenses = guard_defenses - 1 where id = owner.id;
                return 'guard_dog_protected';
            end if;
        end if;
    end if;

    update little_farm_social.plots set remaining = remaining - 1 where id = p_plot;
    insert into little_farm_social.harvests (visitor_id, plot_id, crop)
    values (me, p_plot, plot.crop);
    return plot.crop;
end;
$$;


revoke all on function public.farm_social_visit(uuid) from public, anon, authenticated;
grant execute on function public.farm_social_visit(uuid) to authenticated;

commit;
