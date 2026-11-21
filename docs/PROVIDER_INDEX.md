# ASIX B2B Provider Documentation Index

This directory describes the planned B2B provider layer. None of these documents changes current production behavior.

## Architecture and contracts
- [Provider Integration Architecture](PROVIDER_INTEGRATION_ARCHITECTURE.md)
- [Provider API Contract v1.0](PROVIDER_API_CONTRACT_v1.0.md)
- [Provider Wallet Protocol v1.0](PROVIDER_WALLET_PROTOCOL_v1.0.md)
- [Provider Data Model v1.0](PROVIDER_DATA_MODEL_v1.0.md)
- [Existing ASIX Compatibility Map](EXISTING_ASIX_COMPATIBILITY_MAP_v1.0.md)

## Reliability, testing and operations
- [Partner UAT Test Matrix v1.0](PARTNER_UAT_TEST_MATRIX_v1.0.md)
- [Provider Autopilot Policy v1.0](PROVIDER_AUTOPILOT_POLICY_v1.0.md)
- [Stage 2 Build Plan](PROVIDER_STAGE2_BUILD_PLAN.md)
- [Threat Model](PROVIDER_THREAT_MODEL_v1.0.md)
- [Partner Key Management and Rotation](PROVIDER_KEY_MANAGEMENT_AND_ROTATION_v1.0.md)
- [SLO and Observability](PROVIDER_SLO_AND_OBSERVABILITY_v1.0.md)
- [Incident and Recovery Runbooks](PROVIDER_RUNBOOKS_v1.0.md)
- [Partner Onboarding](PROVIDER_PARTNER_ONBOARDING_v1.0.md)
- [Commercial and Settlement Model](PROVIDER_COMMERCIAL_SETTLEMENT_MODEL_v1.0.md)
- [Game Release and Certification](PROVIDER_GAME_RELEASE_AND_CERTIFICATION_v1.0.md)
- [Disaster Recovery and Backup](PROVIDER_DR_AND_BACKUP_v1.0.md)
- [Privacy and Data Governance](PROVIDER_PRIVACY_AND_DATA_GOVERNANCE_v1.0.md)
- [RACI and Governance](PROVIDER_RACI_AND_GOVERNANCE_v1.0.md)

## Reference implementation
- [Provider reference contracts and simulator](../provider-reference/README.md)
- [Wallet Orchestrator reference state machine](../provider-reference/wallet_orchestrator.ts)
- [Provider ledger journal builder](../provider-reference/ledger.ts)
- [Provider settlement calculator](../provider-reference/settlement_engine.ts)
- [Wallet Orchestrator tests](../provider-reference/wallet_orchestrator_test.ts)
- [Partner HMAC authentication reference](../provider-reference/partner_auth.ts)
- [One-time launch service](../provider-reference/launch_service.ts)
- [Partner circuit breaker and status-query backoff](../provider-reference/resilience.ts)
- [Partner Provider Gateway handler](../provider-reference/provider_gateway.ts)
- [Gateway integration tests](../provider-reference/provider_gateway_test.ts)
- [Circuit breaker tests](../provider-reference/resilience_test.ts)
- [Launch service tests](../provider-reference/launch_service_test.ts)
- [Partner authentication tests](../provider-reference/partner_auth_test.ts)
- [Partner API OpenAPI contract](../provider-reference/openapi/provider-api.yaml)
- [Test-only in-memory repository](../provider-reference/testing/in_memory_repository.ts)
- [Local mock operator wallet simulator guide](../provider-reference/simulator/README.md)
- [Simulator server](../provider-reference/simulator/server.ts)
- [Simulator tests](../provider-reference/simulator/server_test.ts)

## Production boundary
These are engineering design/reference artifacts. They are not deployed provider endpoints, partner-specific wallet integrations, production database migrations, certified games or proof of regulatory authorization. The V154 restore and existing product financial/gameplay validation gates must be closed before production integration work.
