import {
  verifyPartnerRequest,
  type PartnerKeyResolver,
  type ReplayNonceStore,
  type PartnerSignatureOptions,
} from "./partner_auth.ts";
import {
  ProviderLaunchService,
  LaunchRejectedError,
  type LaunchRequestInput,
} from "./launch_service.ts";

export interface PartnerRateLimitDecision {
  allowed: boolean;
  retryAfterSeconds?: number;
}

export interface PartnerRequestRateLimiter {
  consume(partnerCode: string, nowMs: number): Promise<PartnerRateLimitDecision>;
}

export interface ProviderGatewayDependencies {
  keyResolver: PartnerKeyResolver;
  nonceStore: ReplayNonceStore;
  launchService: ProviderLaunchService;
  rateLimiter: PartnerRequestRateLimiter;
  signatureOptions?: PartnerSignatureOptions;
  now?: () => Date;
  correlationId?: () => string;
}

function json(body: unknown, status: number, correlationId: string, headers: HeadersInit = {}): Response {
  const finalHeaders = new Headers(headers);
  finalHeaders.set("content-type", "application/json; charset=utf-8");
  finalHeaders.set("cache-control", "no-store");
  finalHeaders.set("pragma", "no-cache");
  finalHeaders.set("x-correlation-id", correlationId);
  return new Response(JSON.stringify(body), { status, headers: finalHeaders });
}

function errorResponse(
  status: number,
  code: string,
  message: string,
  correlationId: string,
  extra: Record<string, unknown> = {},
): Response {
  return json({
    ok: false,
    error: { code, message, ...extra },
    correlation_id: correlationId,
  }, status, correlationId);
}

function parseLaunchInput(value: unknown): LaunchRequestInput | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const body = value as Record<string, unknown>;
  const keys = [
    "partner_player_ref",
    "partner_session_ref",
    "game_code",
    "currency",
    "jurisdiction",
    "locale",
  ];
  if (Object.keys(body).some((key) => !keys.includes(key)) ||
      keys.some((key) => typeof body[key] !== "string")) return null;
  return {
    partnerPlayerRef: body.partner_player_ref as string,
    partnerSessionRef: body.partner_session_ref as string,
    gameCode: body.game_code as string,
    currency: body.currency as string,
    jurisdiction: body.jurisdiction as string,
    locale: body.locale as string,
  };
}

/**
 * Creates a minimal partner-facing provider gateway handler.
 *
 * No CORS headers are emitted: this is a server-to-server endpoint.
 * Do not expose this handler through permissive browser proxy routes.
 */
export function createProviderGateway(deps: ProviderGatewayDependencies): (request: Request) => Promise<Response> {
  const now = deps.now ?? (() => new Date());
  const correlationId = deps.correlationId ?? (() => crypto.randomUUID());

  return async (request: Request): Promise<Response> => {
    const trace = correlationId();
    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/health") {
      return json({ ok: true, service: "asix-provider-gateway" }, 200, trace);
    }
    if (request.method !== "POST" || url.pathname !== "/provider/v1/launches") {
      return errorResponse(404, "NOT_FOUND", "Endpoint not found.", trace);
    }

    const verified = await verifyPartnerRequest(
      request,
      deps.keyResolver,
      deps.nonceStore,
      {
        ...deps.signatureOptions,
        nowEpochSeconds: deps.signatureOptions?.nowEpochSeconds ??
          Math.floor(now().getTime() / 1000),
      },
    );

    if (!verified.ok) {
      const authMessages: Record<string, string> = {
        SIGNATURE_HEADERS_MISSING: "Required partner signature headers are missing.",
        KEY_UNKNOWN_OR_REVOKED: "Partner key is unknown or revoked.",
        TIMESTAMP_INVALID: "Partner request timestamp is invalid.",
        REQUEST_EXPIRED: "Partner request timestamp is outside the allowed window.",
        NONCE_INVALID: "Partner request nonce is invalid.",
        BODY_TOO_LARGE: "Partner request body exceeds the allowed size.",
        SIGNATURE_INVALID: "Partner request signature is invalid.",
        REPLAY_DETECTED: "Partner request nonce has already been used.",
      };
      return errorResponse(401, verified.error, authMessages[verified.error], trace);
    }

    const rate = await deps.rateLimiter.consume(verified.partnerCode, now().getTime());
    if (!rate.allowed) {
      const retryAfter = Math.max(1, Math.min(3600, Math.floor(rate.retryAfterSeconds ?? 1)));
      return json({
        ok: false,
        error: {
          code: "RATE_LIMITED",
          message: "Partner request rate limit exceeded.",
          retryable: true,
        },
        correlation_id: trace,
      }, 429, trace, { "retry-after": String(retryAfter) });
    }

    let raw: unknown;
    try {
      raw = JSON.parse(new TextDecoder().decode(verified.body));
    } catch {
      return errorResponse(400, "INVALID_JSON", "Request body must be valid JSON.", trace);
    }
    const input = parseLaunchInput(raw);
    if (!input) {
      return errorResponse(400, "INVALID_LAUNCH_CONTEXT", "Required launch fields are missing or invalid.", trace);
    }

    try {
      const issued = await deps.launchService.issueLaunch({
        partnerCode: verified.partnerCode,
        keyId: verified.keyId,
        protocolVersion: verified.protocolVersion,
      }, input);

      return json({
        ok: true,
        launch_url: issued.launchUrl,
        launch_token: issued.launchToken,
        expires_at: issued.expiresAt,
        session_id: issued.sessionId,
        launch_id: issued.launchId,
        policy_version: issued.policyVersion,
      }, 201, trace);
    } catch (error) {
      if (!(error instanceof LaunchRejectedError)) {
        return errorResponse(500, "INTERNAL_ERROR", "The provider could not create the launch.", trace);
      }
      const statusByCode: Record<string, number> = {
        INVALID_LAUNCH_CONTEXT: 400,
        INVALID_VERIFIED_PARTNER_CONTEXT: 401,
        PARTNER_INACTIVE: 403,
        GAME_NOT_ENABLED: 403,
        CURRENCY_NOT_ALLOWED: 403,
        JURISDICTION_NOT_ALLOWED: 403,
        LOCALE_NOT_ALLOWED: 403,
        INVALID_TRUSTED_LAUNCH_BASE_URL: 500,
        INVALID_PARTNER_LAUNCH_TTL: 500,
      };
      const status = statusByCode[error.message] ?? 400;
      const userMessage = status >= 500
        ? "The provider launch configuration is unavailable."
        : "The requested game launch is not permitted.";
      return errorResponse(status, error.message, userMessage, trace);
    }
  };
}
