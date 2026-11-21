import type {
  PartnerHealth,
  PartnerWalletAdapter,
  TransactionStatusQuery,
  WalletCommand,
  WalletResult,
} from "./contracts.ts";

export interface PartnerHttpRequestPlan {
  method: "GET" | "POST";
  /** Relative path below the configured base URL; never an arbitrary host. */
  path: string;
  headers?: Record<string, string>;
  body?: string;
  /** True only for read-only status and health requests. */
  readOnly: boolean;
}

export interface PartnerHttpResponse {
  status: number;
  headers: Headers;
  body: Uint8Array;
}

export interface PartnerRequestSigningInput {
  partnerCode: string;
  credentialReference: string;
  method: "GET" | "POST";
  url: string;
  body: string;
  headers: Headers;
  idempotencyKey?: string;
  timestamp: string;
}

export interface PartnerRequestSigner {
  /**
   * Resolve key material from KMS/secrets manager internally and return the
   * partner protocol's auth/signature headers. Never return or log secret bytes.
   */
  sign(input: PartnerRequestSigningInput): Promise<Record<string, string>>;
}

export interface PartnerWalletProtocol {
  buildWalletRequest(
    operation: "BET" | "WIN" | "REFUND",
    command: WalletCommand,
  ): Promise<PartnerHttpRequestPlan>;
  parseWalletResponse(
    response: PartnerHttpResponse,
    command: WalletCommand,
  ): Promise<WalletResult>;

  buildStatusRequest(query: TransactionStatusQuery): Promise<PartnerHttpRequestPlan>;
  parseStatusResponse(
    response: PartnerHttpResponse,
    query: TransactionStatusQuery,
  ): Promise<WalletResult>;

  buildHealthRequest(partnerCode: string): Promise<PartnerHttpRequestPlan>;
  parseHealthResponse(
    response: PartnerHttpResponse,
    partnerCode: string,
  ): Promise<PartnerHealth>;
}

export interface PartnerHttpAdapterConfig {
  partnerCode: string;
  baseUrl: string;
  credentialReference: string;
  adapterVersion: string;
  protocolVersion: string;
  requestTimeoutMs?: number;
  maxResponseBytes?: number;
  idempotencyHeaderName?: string;
}

export type PartnerFetch = (input: string | URL | Request, init?: RequestInit) => Promise<Response>;

export class PartnerHttpAdapterError extends Error {
  constructor(code: string) {
    super(code);
    this.name = "PartnerHttpAdapterError";
  }
}

function validateConfig(config: PartnerHttpAdapterConfig): URL {
  if (!config.partnerCode || config.partnerCode.length > 128 ||
      !config.credentialReference || !config.adapterVersion || !config.protocolVersion) {
    throw new PartnerHttpAdapterError("INVALID_PARTNER_ADAPTER_CONFIG");
  }
  const base = new URL(config.baseUrl);
  if (base.protocol !== "https:" || base.username || base.password || base.search || base.hash) {
    throw new PartnerHttpAdapterError("INVALID_PARTNER_BASE_URL");
  }
  if (!base.pathname.endsWith("/")) base.pathname += "/";
  const timeout = config.requestTimeoutMs ?? 8_000;
  const maxBytes = config.maxResponseBytes ?? 256 * 1024;
  const idemHeader = config.idempotencyHeaderName ?? "idempotency-key";
  if (!Number.isInteger(timeout) || timeout < 50 || timeout > 60_000 ||
      !Number.isInteger(maxBytes) || maxBytes < 1 || maxBytes > 2 * 1024 * 1024 ||
      !/^[A-Za-z0-9-]{1,64}$/.test(idemHeader)) {
    throw new PartnerHttpAdapterError("INVALID_PARTNER_HTTP_LIMITS");
  }
  return base;
}

function resolveSafeUrl(base: URL, path: string): URL {
  if (!path || path.length > 2_000 || path.startsWith("/") || path.includes("\\") ||
      /^[A-Za-z][A-Za-z0-9+.-]*:/.test(path)) {
    throw new PartnerHttpAdapterError("INVALID_PARTNER_REQUEST_PATH");
  }
  const url = new URL(path, base);
  if (url.protocol !== "https:" || url.origin !== base.origin ||
      !url.pathname.startsWith(base.pathname) || url.username || url.password || url.hash) {
    throw new PartnerHttpAdapterError("PARTNER_REQUEST_TARGET_NOT_ALLOWED");
  }
  return url;
}

function toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  const copy = new Uint8Array(bytes.byteLength);
  copy.set(bytes);
  return copy.buffer;
}

async function readResponseBounded(response: Response, maximum: number): Promise<Uint8Array> {
  const declaredLength = response.headers.get("content-length");
  if (declaredLength && /^[0-9]+$/.test(declaredLength) && Number(declaredLength) > maximum) {
    await response.body?.cancel();
    throw new PartnerHttpAdapterError("PARTNER_RESPONSE_TOO_LARGE");
  }

  const stream = response.body;
  if (!stream) return new Uint8Array(0);

  const reader = stream.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const part = await reader.read();
      if (part.done) break;
      total += part.value.byteLength;
      if (total > maximum) {
        await reader.cancel();
        throw new PartnerHttpAdapterError("PARTNER_RESPONSE_TOO_LARGE");
      }
      chunks.push(part.value);
    }
  } finally {
    reader.releaseLock();
  }

  const output = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    output.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return output;
}

/**
 * Protocol-neutral HTTP adapter. It does not retry any request. All financial
 * operations use a stable idempotency key; uncertain transport outcomes are
 * propagated to WalletOrchestrator, which records UNKNOWN and performs a
 * read-only status query.
 */
export class HttpPartnerWalletAdapter implements PartnerWalletAdapter {
  private readonly base: URL;
  private readonly timeoutMs: number;
  private readonly maxResponseBytes: number;
  private readonly idempotencyHeaderName: string;

  constructor(
    private readonly config: PartnerHttpAdapterConfig,
    private readonly protocol: PartnerWalletProtocol,
    private readonly signer: PartnerRequestSigner,
    private readonly fetcher: PartnerFetch = fetch,
    private readonly now: () => Date = () => new Date(),
  ) {
    this.base = validateConfig(config);
    this.timeoutMs = config.requestTimeoutMs ?? 8_000;
    this.maxResponseBytes = config.maxResponseBytes ?? 256 * 1024;
    this.idempotencyHeaderName = config.idempotencyHeaderName ?? "idempotency-key";
  }

  async debitBet(command: WalletCommand): Promise<WalletResult> {
    return await this.walletCall("BET", command);
  }

  async creditWin(command: WalletCommand): Promise<WalletResult> {
    return await this.walletCall("WIN", command);
  }

  async refund(command: WalletCommand): Promise<WalletResult> {
    return await this.walletCall("REFUND", command);
  }

  async getTransactionStatus(query: TransactionStatusQuery): Promise<WalletResult> {
    this.assertPartner(query.partnerCode);
    const plan = await this.protocol.buildStatusRequest(query);
    if (!plan.readOnly) throw new PartnerHttpAdapterError("STATUS_REQUEST_MUST_BE_READ_ONLY");
    const response = await this.send(plan);
    return await this.protocol.parseStatusResponse(response, query);
  }

  async healthCheck(context: {
    partnerCode: string;
    correlationId: string;
    adapterVersion: string;
    protocolVersion: string;
  }): Promise<PartnerHealth> {
    this.assertPartner(context.partnerCode);
    const plan = await this.protocol.buildHealthRequest(context.partnerCode);
    if (!plan.readOnly) throw new PartnerHttpAdapterError("HEALTH_REQUEST_MUST_BE_READ_ONLY");
    const response = await this.send(plan);
    return await this.protocol.parseHealthResponse(response, context.partnerCode);
  }

  private async walletCall(
    operation: "BET" | "WIN" | "REFUND",
    command: WalletCommand,
  ): Promise<WalletResult> {
    this.assertPartner(command.partnerCode);
    if (command.adapterVersion !== this.config.adapterVersion ||
        command.protocolVersion !== this.config.protocolVersion) {
      throw new PartnerHttpAdapterError("PARTNER_ADAPTER_VERSION_MISMATCH");
    }
    const plan = await this.protocol.buildWalletRequest(operation, command);
    if (plan.readOnly || plan.method !== "POST" || !plan.body) {
      throw new PartnerHttpAdapterError("WALLET_REQUEST_MUST_BE_POST_WITH_BODY");
    }
    const response = await this.send(plan, command.idempotencyKey);
    return await this.protocol.parseWalletResponse(response, command);
  }

  private assertPartner(partnerCode: string): void {
    if (partnerCode !== this.config.partnerCode) {
      throw new PartnerHttpAdapterError("PARTNER_SCOPE_MISMATCH");
    }
  }

  private async send(plan: PartnerHttpRequestPlan, idempotencyKey?: string): Promise<PartnerHttpResponse> {
    if ((plan.method !== "GET" && plan.method !== "POST") ||
        (plan.method === "GET" && plan.body !== undefined)) {
      throw new PartnerHttpAdapterError("INVALID_PARTNER_REQUEST_PLAN");
    }
    const url = resolveSafeUrl(this.base, plan.path);
    const headers = new Headers(plan.headers ?? {});
    headers.set("accept", "application/json");
    if (plan.body !== undefined) headers.set("content-type", "application/json");
    if (idempotencyKey) headers.set(this.idempotencyHeaderName, idempotencyKey);

    const timestamp = this.now().toISOString();
    if (!Number.isFinite(Date.parse(timestamp))) throw new PartnerHttpAdapterError("INVALID_SYSTEM_CLOCK");
    const signedHeaders = await this.signer.sign({
      partnerCode: this.config.partnerCode,
      credentialReference: this.config.credentialReference,
      method: plan.method,
      url: url.toString(),
      body: plan.body ?? "",
      headers: new Headers(headers),
      idempotencyKey,
      timestamp,
    });
    for (const [name, value] of Object.entries(signedHeaders)) {
      const normalizedName = name.toLowerCase();
      if (["host", "content-length", "connection", "transfer-encoding"].includes(normalizedName)) {
        throw new PartnerHttpAdapterError("SIGNER_RETURNED_FORBIDDEN_HEADER");
      }
      if (idempotencyKey && normalizedName === this.idempotencyHeaderName.toLowerCase() &&
          value !== idempotencyKey) {
        throw new PartnerHttpAdapterError("SIGNER_CHANGED_IDEMPOTENCY_KEY");
      }
      headers.set(name, value);
    }

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    let response: Response;
    try {
      response = await this.fetcher(url, {
        method: plan.method,
        headers,
        body: plan.body,
        redirect: "error",
        signal: controller.signal,
        cache: "no-store",
      });
    } catch {
      if (controller.signal.aborted) throw new PartnerHttpAdapterError("PARTNER_REQUEST_TIMEOUT");
      throw new PartnerHttpAdapterError("PARTNER_TRANSPORT_UNKNOWN");
    } finally {
      clearTimeout(timer);
    }

    if (response.redirected) {
      await response.body?.cancel();
      throw new PartnerHttpAdapterError("PARTNER_REDIRECT_REJECTED");
    }
    const body = await readResponseBounded(response, this.maxResponseBytes);
    return {
      status: response.status,
      headers: new Headers(response.headers),
      body,
    };
  }
}
