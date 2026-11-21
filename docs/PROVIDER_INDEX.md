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

## Reference implementation
- [Provider reference contracts and simulator](../provider-reference/README.md)
- [Local mock operator wallet simulator guide](../provider-reference/simulator/README.md)
- [Simulator server](../provider-reference/simulator/server.ts)
- [Simulator tests](../provider-reference/simulator/server_test.ts)

## Production boundary
These are engineering design/reference artifacts. They are not deployed provider endpoints, partner-specific wallet integrations, production database migrations, certified games or proof of regulatory authorization. The V154 restore and existing product financial/gameplay validation gates must be closed before production integration work.
