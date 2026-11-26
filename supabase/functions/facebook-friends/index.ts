import { createClient } from "npm:@supabase/supabase-js@2";

const graphUrl = "https://graph.facebook.com/v27.0";

async function graph(path: string, token: string, after?: string) {
  const url = new URL(`${graphUrl}/${path}`);
  if (after) url.searchParams.set("after", after);
  const result = await fetch(url, {
    headers: { Authorization: `Bearer ${token}` },
    signal: AbortSignal.timeout(8000),
  });
  if (!result.ok) throw new Error("graph_unavailable");
  return await result.json();
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return new Response(null, { status: 405 });

  const jwt = request.headers.get("Authorization")?.match(/^Bearer (\S+)$/i)?.[1];
  if (!jwt) return new Response(null, { status: 401 });

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
  const { data: { user }, error: authError } = await admin.auth.getUser(jwt);
  if (authError || !user) return new Response(null, { status: 401 });

  try {
    const { providerToken } = await request.json();
    if (typeof providerToken !== "string" || !providerToken || providerToken.length > 4096) {
      return new Response(null, { status: 400 });
    }

    const identity = await graph("me?fields=id", providerToken);
    const facebookId = identity.id;
    if (typeof facebookId !== "string") return new Response(null, { status: 403 });

    const permissions = await graph("me/permissions", providerToken);
    if (!Array.isArray(permissions.data) || permissions.paging?.next) {
      throw new Error("invalid_permissions");
    }
    const granted = permissions.data.some(
      (entry: { permission: string; status: string }) =>
        entry.permission === "user_friends" && entry.status === "granted",
    );

    const friends = new Set<string>();
    if (granted) {
      let after: string | undefined;
      for (let page = 0; ; page++) {
        if (page >= 50) throw new Error("incomplete_friends");
        const result = await graph("me/friends?fields=id&limit=100", providerToken, after);
        if (!Array.isArray(result.data)) throw new Error("invalid_friends");
        for (const entry of result.data) {
          if (typeof entry.id !== "string") throw new Error("invalid_friend");
          friends.add(entry.id);
        }
        if (!result.paging?.next) break;
        const cursor = result.paging.cursors?.after;
        if (typeof cursor !== "string" || !cursor || cursor === after) {
          throw new Error("invalid_cursor");
        }
        after = cursor;
      }
    }

    const { error } = await admin.rpc("farm_social_sync_facebook", {
      p_player: user.id,
      p_facebook_id: facebookId,
      p_friends: [...friends],
    });
    if (error) return new Response(null, { status: 503 });
    return Response.json({ granted });
  } catch {
    return new Response(null, { status: 502 });
  }
});
