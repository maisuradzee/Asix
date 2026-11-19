# Export SQL guide

`casino_handover_catalog.sql` is a read-only catalog inspection aid. It returns the exact function definitions and object metadata, but it is not a pg_dump replacement. Use the native CLI exporter for the authoritative current schema SQL.

The query deliberately reports commission recipient presence without returning the source Auth user UUID. The recipient must be remapped to a new destination Auth user during restoration.
