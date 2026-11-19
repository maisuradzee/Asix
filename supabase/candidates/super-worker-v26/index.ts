// ASIX super-worker — standalone Supabase Edge Function
// No @supabase/supabase-js import is required. Uses Deno.serve + fetch only.

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-supabase-api-version",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Max-Age": "86400",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
}

async function rpc(
  projectUrl: string,
  apiKey: string,
  functionName: string,
  args: unknown,
  bearerToken = apiKey,
): Promise<unknown> {
  const response = await fetch(`${projectUrl}/rest/v1/rpc/${functionName}`, {
    method: "POST",
    headers: {
      apikey: apiKey,
      Authorization: `Bearer ${bearerToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(args),
  });

  const raw = await response.text();
  let data: unknown = null;
  if (raw) {
    try { data = JSON.parse(raw); } catch { data = raw; }
  }

  if (!response.ok) {
    const error = new Error(`RPC_${functionName}_HTTP_${response.status}`) as Error & {
      status?: number;
      data?: unknown;
    };
    error.status = response.status;
    error.data = data;
    throw error;
  }
  return data;
}

Deno.serve(async (request: Request): Promise<Response> => {
  // CORS preflight must not require auth or call Supabase.
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse({ ok: false, error: "METHOD_NOT_ALLOWED" }, 405);
  }

  const traceId = crypto.randomUUID();
  let stage = "configuration";
  let actionId: number | null = null;

  try {
    const projectUrl = (Deno.env.get("PROJECT_URL") || "").replace(/\/$/, "");
    const anonKey = Deno.env.get("PUBLIC_KEY") || "";
    const serviceRoleKey = Deno.env.get("SERVICE_ROLE_KEY") || "";

    if (!projectUrl || !anonKey || !serviceRoleKey) {
      return jsonResponse({ ok: false, error: "SERVER_CONFIGURATION_MISSING", trace_id: traceId }, 500);
    }

    stage = "authorization";
    const authorization = request.headers.get("Authorization") || "";
    const userToken = authorization.replace(/^Bearer\s+/i, "").trim();
    if (!userToken) {
      return jsonResponse({ ok: false, error: "AUTH_REQUIRED", trace_id: traceId }, 401);
    }

    stage = "parse_body";
    const body = await request.json().catch(() => null);
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      return jsonResponse({ ok: false, error: "INVALID_JSON", trace_id: traceId }, 400);
    }

    // Normal game actions now use one authenticated Postgres RPC. auth.uid()
    // is derived from the caller JWT; submit + process happen in one transaction.
    if (body.action_type !== undefined && body.room_id !== undefined) {
      stage = "atomic_submit_process_rpc";
      const roomId = String(body.room_id || "");
      const actionType = String(body.action_type || "");
      if (!isUuid(roomId)) {
        return jsonResponse({ ok: false, error: "INVALID_ROOM_ID", trace_id: traceId }, 400);
      }
      const allowedActions = ["ready", "start", "redeal", "play_card", "fold", "raise", "call", "leave", "reconnect"];
      if (!allowedActions.includes(actionType)) {
        return jsonResponse({ ok: false, error: "INVALID_ACTION_TYPE", trace_id: traceId }, 400);
      }
      const expectedVersion = Number(body.expected_version);
      if (!Number.isSafeInteger(expectedVersion) || expectedVersion < 0) {
        return jsonResponse({ ok: false, error: "INVALID_EXPECTED_VERSION", trace_id: traceId }, 400);
      }
      const result = await rpc(
        projectUrl,
        anonKey,
        "qcard_submit_process_action",
        {
          p_room_id: roomId,
          p_action_type: actionType,
          p_payload: body.payload && typeof body.payload === "object" && !Array.isArray(body.payload) ? body.payload : {},
          p_expected_version: expectedVersion,
        },
        userToken,
      );
      const outcome = result as { action_id?: number; ok?: boolean; recoverable_action?: boolean; result?: unknown; error?: string };
      actionId = Number(outcome?.action_id) || null;
      if (outcome?.ok === false && outcome?.recoverable_action === true) {
        return jsonResponse({
          ok: false,
          stage,
          error: (outcome as { error?: string }).error || "ACTION_PROCESSING_PENDING",
          action_id: actionId,
          recoverable_action: true,
          trace_id: traceId,
        }, 500);
      }
      return jsonResponse({
        ok: outcome?.ok === true,
        action_id: actionId,
        result: outcome?.result ?? outcome,
        recoverable_action: false,
        trace_id: traceId,
      }, outcome?.ok === false ? 409 : 200);
    }

    // Heartbeat/recovery/timeout work is bundled into one authenticated RPC.
    // auth.uid() comes from the caller JWT; no /auth/v1/user request is needed.
    if (body.heartbeat === true) {
      stage = "heartbeat_bundle_validate";
      const roomId = String(body.room_id || "");
      if (!isUuid(roomId)) {
        return jsonResponse({ ok: false, error: "INVALID_ROOM_ID", trace_id: traceId }, 400);
      }
      stage = "heartbeat_bundle_rpc";
      const bundle = await rpc(
        projectUrl,
        anonKey,
        "qcard_asix_heartbeat_bundle",
        { p_room_id: roomId },
        userToken,
      );
      const bundleResult = bundle as { heartbeat?: { cancelled?: boolean } };
      return jsonResponse({
        ok: true,
        heartbeat: true,
        cancelled: bundleResult?.heartbeat?.cancelled === true,
        result: bundle,
        trace_id: traceId,
      });
    }

    // Heartbeat and recovery calls still need the verified user id.
    const userResponse = await fetch(`${projectUrl}/auth/v1/user`, {
      headers: { apikey: anonKey, Authorization: `Bearer ${userToken}` },
    });
    const userData = await userResponse.json().catch(() => null);
    if (!userResponse.ok || !userData?.id) {
      return jsonResponse({
        ok: false,
        error: "AUTH_REQUIRED",
        auth_status: userResponse.status,
        trace_id: traceId,
      }, 401);
    }
    const userId = String(userData.id);

    // Process an already-created action.
    if (body.action_id !== undefined) {
      stage = "action_id_validate";
      const parsedActionId = Number(body.action_id);
      if (!Number.isSafeInteger(parsedActionId) || parsedActionId < 1) {
        return jsonResponse({ ok: false, error: "INVALID_ACTION_ID", trace_id: traceId }, 400);
      }
      actionId = parsedActionId;
      stage = "process_action_rpc";
      const result = await rpc(
        projectUrl,
        serviceRoleKey,
        "qcard_process_action",
        { p_action_id: parsedActionId, p_actor_user_id: userId },
      );
      return jsonResponse({ ok: true, action_id: actionId, result, trace_id: traceId });
    }

    // Optional combined submit + process mode.
    stage = "action_validate";
    const roomId = String(body.room_id || "");
    const actionType = String(body.action_type || "");
    if (!isUuid(roomId)) {
      return jsonResponse({ ok: false, error: "INVALID_ROOM_ID", trace_id: traceId }, 400);
    }
    const allowedActions = ["ready", "start", "redeal", "play_card", "fold", "raise", "call", "leave", "reconnect"];
    if (!allowedActions.includes(actionType)) {
      return jsonResponse({ ok: false, error: "INVALID_ACTION_TYPE", trace_id: traceId }, 400);
    }

    stage = "version_lookup";
    let expectedVersion = body.expected_version;
    if (expectedVersion === undefined || expectedVersion === null) {
      const stateResponse = await fetch(
        `${projectUrl}/rest/v1/qcard_game_state?select=version&room_id=eq.${encodeURIComponent(roomId)}`,
        { headers: { apikey: serviceRoleKey, Authorization: `Bearer ${serviceRoleKey}` } },
      );
      const rows = await stateResponse.json().catch(() => []);
      if (!stateResponse.ok || !rows?.[0]) {
        return jsonResponse({ ok: false, error: "GAME_STATE_NOT_FOUND", details: rows, trace_id: traceId }, 404);
      }
      expectedVersion = rows[0].version;
    }
    expectedVersion = Number(expectedVersion);
    if (!Number.isSafeInteger(expectedVersion) || expectedVersion < 0) {
      return jsonResponse({ ok: false, error: "INVALID_EXPECTED_VERSION", trace_id: traceId }, 400);
    }

    stage = "submit_action_rpc";
    const actionIdResult = await rpc(
      projectUrl,
      anonKey,
      "qcard_submit_action",
      {
        p_room_id: roomId,
        p_action_type: actionType,
        p_payload: body.payload && typeof body.payload === "object" && !Array.isArray(body.payload) ? body.payload : {},
        p_expected_version: expectedVersion,
      },
      userToken,
    );
    const parsedActionId = Number(actionIdResult);
    if (!Number.isSafeInteger(parsedActionId) || parsedActionId < 1) {
      throw new Error(`INVALID_SUBMITTED_ACTION_ID:${String(actionIdResult)}`);
    }

    actionId = parsedActionId;
    stage = "process_action_rpc";
    const result = await rpc(
      projectUrl,
      serviceRoleKey,
      "qcard_process_action",
      { p_action_id: parsedActionId, p_actor_user_id: userId },
    );
    return jsonResponse({ ok: true, action_id: actionId, result, trace_id: traceId });
  } catch (caught) {
    const error = caught as Error & { status?: number; data?: unknown };
    console.error("ASIX_WORKER_FAILURE", {
      trace_id: traceId,
      stage,
      error: error?.message || String(caught),
      status: error?.status || 500,
      data: error?.data ?? null,
    });
    const status = error?.status && error.status >= 400 && error.status < 600 ? error.status : 500;
    return jsonResponse({
      ok: false,
      stage,
      error: error?.message || String(caught),
      details: error?.data ?? null,
      trace_id: traceId,
      action_id: actionId,
      recoverable_action: actionId !== null,
    }, status);
  }
});
