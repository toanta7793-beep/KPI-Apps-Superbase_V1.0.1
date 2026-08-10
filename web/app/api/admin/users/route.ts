import { createClient } from "@supabase/supabase-js";

type ProfileInput = {
  auth_user_id?: string;
  email?: string;
  password?: string;
  display_name?: string;
  role_code?: string;
  is_active?: boolean;
  worker_id?: string | null;
  team_ids?: string[];
  note?: string | null;
};

const json = (body: unknown, status = 200) =>
  Response.json(body, { status, headers: { "Cache-Control": "no-store" } });

function environment() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const publishable = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  const secret = process.env.SUPABASE_SECRET_KEY;
  if (!url || !publishable || !secret) throw new Error("SERVER_AUTH_NOT_CONFIGURED");
  return { url, publishable, secret };
}

async function authorizedClients(request: Request) {
  const token = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "").trim();
  if (!token) throw new Error("MISSING_ACCESS_TOKEN");
  const env = environment();
  const caller = createClient(env.url, env.publishable, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: identity, error: identityError } = await caller.rpc("get_my_access");
  if (identityError || identity?.[0]?.role_code !== "ADMIN") throw new Error("FORBIDDEN");
  const admin = createClient(env.url, env.secret, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  return { caller, admin };
}

async function listProfiles(caller: Awaited<ReturnType<typeof authorizedClients>>["caller"]) {
  const { data, error } = await caller.rpc("admin_list_profiles");
  if (error) throw error;
  return data || [];
}

export async function GET(request: Request) {
  try {
    const { caller, admin } = await authorizedClients(request);
    const [profiles, authResult] = await Promise.all([
      listProfiles(caller),
      admin.auth.admin.listUsers({ page: 1, perPage: 1000 }),
    ]);
    if (authResult.error) throw authResult.error;
    const authById = new Map(authResult.data.users.map((user) => [user.id, user]));
    return json({
      users: profiles.map((profile: Record<string, unknown>) => {
        const authUser = authById.get(String(profile.auth_user_id));
        return {
          ...profile,
          email: authUser?.email || "",
          last_sign_in_at: authUser?.last_sign_in_at || null,
          banned_until: authUser?.banned_until || null,
        };
      }),
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "UNKNOWN_ERROR";
    return json({ error: message }, message === "FORBIDDEN" ? 403 : 400);
  }
}

export async function POST(request: Request) {
  let createdUserId = "";
  try {
    const { caller, admin } = await authorizedClients(request);
    const input = (await request.json()) as ProfileInput;
    const email = input.email?.trim().toLowerCase() || "";
    const password = input.password || "";
    if (!email || password.length < 8) return json({ error: "EMAIL_OR_PASSWORD_INVALID" }, 400);
    const { data, error } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { display_name: input.display_name?.trim() || email },
    });
    if (error || !data.user) throw error || new Error("AUTH_USER_NOT_CREATED");
    createdUserId = data.user.id;
    const { error: profileError } = await caller.rpc("admin_set_profile", {
      p_auth_user_id: createdUserId,
      p_display_name: input.display_name || "",
      p_role_code: input.role_code || "XEM",
      p_is_active: input.is_active !== false,
      p_worker_id: input.worker_id || null,
      p_team_ids: input.team_ids || [],
      p_note: input.note || null,
    });
    if (profileError) throw profileError;
    return json({ id: createdUserId }, 201);
  } catch (error) {
    try {
      if (createdUserId) {
        const { admin } = await authorizedClients(request);
        await admin.auth.admin.deleteUser(createdUserId);
      }
    } catch { /* compensation is best-effort and never hides the original error */ }
    return json({ error: error instanceof Error ? error.message : "CREATE_USER_FAILED" }, 400);
  }
}

export async function PATCH(request: Request) {
  try {
    const { caller, admin } = await authorizedClients(request);
    const input = (await request.json()) as ProfileInput;
    if (!input.auth_user_id) return json({ error: "AUTH_USER_ID_REQUIRED" }, 400);
    const profiles = await listProfiles(caller);
    const previous = profiles.find((item: Record<string, unknown>) => item.auth_user_id === input.auth_user_id);
    if (!previous) return json({ error: "PROFILE_NOT_FOUND" }, 404);

    const setProfile = (value: ProfileInput | Record<string, unknown>) => caller.rpc("admin_set_profile", {
      p_auth_user_id: input.auth_user_id,
      p_display_name: value.display_name || "",
      p_role_code: value.role_code || "XEM",
      p_is_active: value.is_active !== false,
      p_worker_id: value.worker_id || null,
      p_team_ids: value.team_ids || [],
      p_note: value.note || null,
    });
    const { error: profileError } = await setProfile(input);
    if (profileError) throw profileError;

    const authPatch: Record<string, unknown> = {
      user_metadata: { display_name: input.display_name?.trim() || "" },
      ban_duration: input.is_active === false ? "876000h" : "none",
    };
    if (input.email) authPatch.email = input.email.trim().toLowerCase();
    if (input.password) {
      if (input.password.length < 8) {
        await setProfile(previous);
        return json({ error: "PASSWORD_TOO_SHORT" }, 400);
      }
      authPatch.password = input.password;
    }
    const { error: authError } = await admin.auth.admin.updateUserById(input.auth_user_id, authPatch);
    if (authError) {
      await setProfile(previous);
      throw authError;
    }
    return json({ ok: true });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "UPDATE_USER_FAILED" }, 400);
  }
}
