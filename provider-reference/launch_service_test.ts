import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  ProviderLaunchService,
  LaunchRejectedError,
  type LaunchTokenStore,
  type StoredLaunchToken,
  type PartnerLaunchPolicy,
  type PartnerLaunchPolicyResolver,
  type VerifiedPartnerContext,
  type LaunchClaims,
} from "./launch_service.ts";

class MemoryLaunchStore implements LaunchTokenStore {
  readonly rows = new Map<string, StoredLaunchToken>();

  async create(record: StoredLaunchToken): Promise<void> {
    if (this.rows.has(record.tokenHash)) throw new Error("TOKEN_HASH_CONFLICT");
    this.rows.set(record.tokenHash, record);
  }

  async consumeOnce(tokenHash: string, now: string): Promise<LaunchClaims | null> {
    const record = this.rows.get(tokenHash);
    if (!record || record.consumedAt || Date.parse(record.claims.expiresAt) <= Date.parse(now)) {
      return null;
    }
    record.consumedAt = now;
    return record.claims;
  }
}

const partner: VerifiedPartnerContext = {
  partnerCode: "operator-demo",
  keyId: "key-2026-01",
  protocolVersion: "provider-v1",
};

const policy: PartnerLaunchPolicy = {
  partnerCode: "operator-demo",
  active: true,
  allowedGameCodes: ["ASIX_CARD"],
  allowedCurrencies: ["GEL"],
  allowedJurisdictions: ["GE"],
  allowedLocales: ["ka-GE", "en-GB"],
  launchBaseUrl: "https://games.asix.example.invalid/play",
  tokenTtlSeconds: 60,
  policyVersion: "policy-7",
};

const resolver: PartnerLaunchPolicyResolver = {
  resolve: async (code) => code === policy.partnerCode ? policy : null,
};

const input = {
  partnerPlayerRef: "pseudonymous-player-77",
  partnerSessionRef: "operator-session-777",
  gameCode: "ASIX_CARD",
  currency: "GEL",
  jurisdiction: "GE",
  locale: "ka-GE",
};

Deno.test("launch issuance stores only a token hash and returns short-lived token", async () => {
  const store = new MemoryLaunchStore();
  const fixedNow = new Date("2026-11-21T08:00:00.000Z");
  const service = new ProviderLaunchService(resolver, store, { now: () => fixedNow });

  const issued = await service.issueLaunch(partner, input);
  assertEquals(issued.policyVersion, "policy-7");
  assertEquals(Date.parse(issued.expiresAt) - fixedNow.getTime(), 60_000);
  assertEquals(issued.launchUrl.includes(issued.launchToken), false);
  assertEquals(store.rows.size, 1);
  const stored = [...store.rows.values()][0];
  assertEquals(stored.tokenHash === issued.launchToken, false);
  assertEquals(stored.claims.partnerPlayerRef, input.partnerPlayerRef);
});

Deno.test("launch token can be consumed exactly once", async () => {
  const store = new MemoryLaunchStore();
  const service = new ProviderLaunchService(resolver, store);
  const issued = await service.issueLaunch(partner, input);
  const claims = await service.consumeLaunchToken(issued.launchToken);
  assertEquals(claims.partnerCode, partner.partnerCode);
  await assertRejects(
    () => service.consumeLaunchToken(issued.launchToken),
    LaunchRejectedError,
    "TOKEN_EXPIRED_OR_ALREADY_USED",
  );
});

Deno.test("expired launch token is rejected", async () => {
  const store = new MemoryLaunchStore();
  let now = new Date("2026-11-21T08:00:00.000Z");
  const service = new ProviderLaunchService(resolver, store, { now: () => now });
  const issued = await service.issueLaunch(partner, input);
  now = new Date("2026-11-21T08:02:00.000Z");
  await assertRejects(
    () => service.consumeLaunchToken(issued.launchToken),
    LaunchRejectedError,
    "TOKEN_EXPIRED_OR_ALREADY_USED",
  );
});

Deno.test("disabled game, unsupported currency and wrong jurisdiction are rejected", async () => {
  const store = new MemoryLaunchStore();
  const service = new ProviderLaunchService(resolver, store);
  await assertRejects(
    () => service.issueLaunch(partner, { ...input, gameCode: "OTHER_GAME" }),
    LaunchRejectedError,
    "GAME_NOT_ENABLED",
  );
  await assertRejects(
    () => service.issueLaunch(partner, { ...input, currency: "USD" }),
    LaunchRejectedError,
    "CURRENCY_NOT_ALLOWED",
  );
  await assertRejects(
    () => service.issueLaunch(partner, { ...input, jurisdiction: "XX" }),
    LaunchRejectedError,
    "JURISDICTION_NOT_ALLOWED",
  );
});

Deno.test("inactive partner and invalid launch base URL are rejected", async () => {
  const store = new MemoryLaunchStore();
  const inactiveResolver: PartnerLaunchPolicyResolver = {
    resolve: async () => ({ ...policy, active: false }),
  };
  const service = new ProviderLaunchService(inactiveResolver, store);
  await assertRejects(
    () => service.issueLaunch(partner, input),
    LaunchRejectedError,
    "PARTNER_INACTIVE",
  );

  const invalidUrlResolver: PartnerLaunchPolicyResolver = {
    resolve: async () => ({ ...policy, launchBaseUrl: "http://unsafe.example.invalid" }),
  };
  const invalidService = new ProviderLaunchService(invalidUrlResolver, store);
  await assertRejects(
    () => invalidService.issueLaunch(partner, input),
    LaunchRejectedError,
    "INVALID_TRUSTED_LAUNCH_BASE_URL",
  );
});
