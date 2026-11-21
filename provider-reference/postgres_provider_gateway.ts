/**
 * Composition root for a durable ASIX Provider Gateway.
 *
 * It wires the signed HMAC key resolver, replay nonce store and one-time
 * PostgreSQL LaunchTokenStore into the existing server-to-server gateway.
 * The database executor, KMS/Secrets Manager key adapter, currency registry,
 * partner policy resolver and distributed rate limiter are injected by the
 * deployment. This module opens no connections and reads no environment
 * variables or secrets.
 */
import {
  createProviderGateway,
  type PartnerRequestRateLimiter,
} from "./provider_gateway.ts";
import {
  ProviderLaunchService,
  type LaunchServiceOptions,
  type PartnerLaunchPolicyResolver,
} from "./launch_service.ts";
import type { PartnerSignatureOptions } from "./partner_auth.ts";
import type { ProviderPgExecutor } from "./postgres_repository.ts";
import {
  PostgresLaunchTokenStore,
  PostgresPartnerKeyResolver,
  PostgresReplayNonceStore,
  type CurrencyExponentRegistry,
  type ManagedHmacKeyProvider,
} from "./postgres_gateway_adapters.ts";
import { ProviderPostgresRepository } from "./postgres_repository.ts";

export interface PostgresProviderGatewayOptions {
  database: ProviderPgExecutor;
  managedKeys: ManagedHmacKeyProvider;
  currencies: CurrencyExponentRegistry;
  policies: PartnerLaunchPolicyResolver;
  rateLimiter: PartnerRequestRateLimiter;
  launchOptions?: LaunchServiceOptions;
  signatureOptions?: PartnerSignatureOptions;
  now?: () => Date;
  correlationId?: () => string;
}

/**
 * Builds the Gateway handler over the injected durable database + KMS
 * adapters. Rate limiting is intentionally injected: production deployments
 * must use a shared, distributed limiter (not per-process memory state).
 */
export function createPostgresProviderGateway(
  options: PostgresProviderGatewayOptions,
): (request: Request) => Promise<Response> {
  const repository = new ProviderPostgresRepository(options.database);
  const keyResolver = new PostgresPartnerKeyResolver(repository, options.managedKeys);
  const nonceStore = new PostgresReplayNonceStore(repository);
  const launchTokens = new PostgresLaunchTokenStore(repository, options.currencies);

  const launchOptions: LaunchServiceOptions = {
    ...options.launchOptions,
    ...(options.launchOptions?.now || !options.now ? {} : { now: options.now }),
  };
  const launchService = new ProviderLaunchService(
    options.policies,
    launchTokens,
    launchOptions,
  );

  return createProviderGateway({
    keyResolver,
    nonceStore,
    launchService,
    rateLimiter: options.rateLimiter,
    ...(options.signatureOptions ? { signatureOptions: options.signatureOptions } : {}),
    ...(options.now ? { now: options.now } : {}),
    ...(options.correlationId ? { correlationId: options.correlationId } : {}),
  });
}
