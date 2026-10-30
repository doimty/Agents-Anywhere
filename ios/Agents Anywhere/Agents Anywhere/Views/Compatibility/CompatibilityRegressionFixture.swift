#if DEBUG
nonisolated enum CompatibilityRegressionFixtures {
    static let snapshot = #"""
{
  "approvals": [],
  "catalogs": {},
  "effectiveCapabilities": {
    "capabilities": [
      {
        "allowed": true,
        "available": true,
        "capabilityId": "session.send_message",
        "parameters": {},
        "runtime": "claude",
        "runtimeId": "rti_work",
        "scope": "runtime",
        "sessionId": null,
        "supported": true,
        "unavailableReason": null,
        "version": "1"
      }
    ],
    "revision": 10
  },
  "eventCursor": "seq:10",
  "notices": [],
  "runtimeCapabilities": {
    "capabilities": [
      {
        "allowed": true,
        "available": true,
        "capabilityId": "session.send_message",
        "parameters": {},
        "runtime": "claude",
        "runtimeId": "rti_work",
        "scope": "runtime",
        "sessionId": null,
        "supported": true,
        "unavailableReason": null,
        "version": "1"
      }
    ],
    "revision": 10
  },
  "serverTime": "2026-09-05T12:00:00Z",
  "session": {
    "archiveSource": null,
    "archived": false,
    "archivedAt": null,
    "connectorId": "device",
    "connectorStatus": "online",
    "cwd": "/workspace",
    "externalSessionId": null,
    "id": "compatibility-session",
    "lastActivityAt": null,
    "lastItemAt": null,
    "lastItemOrderSeq": null,
    "lastReadSeq": 0,
    "lastSyncedAt": null,
    "latestTurnEndSeq": 0,
    "pinned": false,
    "pinnedAt": null,
    "projectId": "project",
    "runtime": "dsh",
    "runtimeId": "rti_work",
    "runtimeName": "DSH",
    "runtimeType": "dsh",
    "runtimeTypeDisplayName": null,
    "sortAt": null,
    "sourceAvailability": "available",
    "sourceAvailabilityReason": null,
    "sourceAvailabilityUpdatedAt": null,
    "sourceObservationOrigin": null,
    "sourceObservedAt": null,
    "status": "idle",
    "takeover": true,
    "title": "Long conversation",
    "unread": false,
    "updatedSeq": 10,
    "userArchived": false
  },
  "state": {
    "createdAt": "2026-09-05T12:00:00Z",
    "error": null,
    "externalSessionId": null,
    "metadata": {},
    "runtime": "dsh",
    "runtimeId": "rti_work",
    "runtimeType": "dsh",
    "selections": {
      "effort": null,
      "model": "sel_model"
    },
    "sessionId": "compatibility-session",
    "status": "idle",
    "statusReason": null,
    "updatedAt": "2026-09-05T12:00:00Z",
    "updatedSeq": 10
  },
  "timeline": {
    "items": [],
    "hasMore": true,
    "nextSeq": 100
  }
}
"""#
}
#endif
