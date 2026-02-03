## Provider Implementation Spec

### 1) Purpose

A **Provider** is a standalone executable that runs:

* one **Matter Node** (the provider’s “bridge/gateway” node)
* an **Admin JSON API** for local management
* a **Device Registry** of bridged sub-devices (“device instances”) exposed as Matter endpoints under the provider node

Each Provider is commissioned independently (multiple pairings tolerated). Device instances are bridged endpoints inside the Provider node.

---

### 2) Terminology

* **Provider Node**: the Matter node implemented by the provider executable.
* **Device Instance**: a bridged sub-device managed by the provider and represented as one (or a small set of) Matter endpoints.
* **Device Type**: a template describing configuration schema + endpoint/cluster composition for a device instance.

---

### 3) Required Behaviors

#### 3.1 Matter behavior

* The provider runs **exactly one** Matter node.
* Each Device Instance is exposed as a **stable endpoint** (or endpoint set) under that node.
* The provider must support controller interactions for bridged endpoints:

  * attribute reads/writes
  * command invokes
  * subscriptions & reporting for attribute changes
* Matter communications may use ephemeral ports; the provider must advertise correct reachability via operational discovery (mDNS) as required by the Matter stack.

#### 3.2 Device lifecycle

The provider must support:

* creating a new device instance (via JSON API)
* deleting a device instance (via JSON API)
* updating device settings (via JSON API)
* refreshing device state and emitting attribute reports as state changes

Optional:

* automatic discovery; if present, discovered devices must be represented in a way that does not cause uncontrolled endpoint churn.

---

### 4) Persistence Requirements

* All persistent storage must live under a folder named exactly the same as the executable (e.g., executable `modbus_provider` ⇒ storage folder `modbus_provider/` under a base path).
* The provider must persist, at minimum:

  * device instances (IDs, types, settings)
  * endpoint assignment mapping (device instance → endpoint id(s))
  * Matter fabric / credentials for the provider node (pairings survive restarts)

(Exact storage layout is implementation-defined.)

---

### 5) Command Line Interface

#### 5.1 Required CLI options

* `--http <host:port>`

  * Binds the Admin API.
  * Example: `--http 127.0.0.1:8080`
* `--data <path>`

  * Base directory under which the provider stores its folder named after the executable.
  * If omitted, defaults to current working directory.

#### 5.2 Optional CLI options

* `--bearer <token>`

  * If provided, enables Bearer authentication for the Admin API.
  * If omitted, **no authorization is performed** (all endpoints are open).

**Auth behavior**

* When `--bearer` is set, all requests MUST include:

  * `Authorization: Bearer <token>`
* Missing/invalid token ⇒ `401` with JSON error body.

---

### 6) Admin JSON API

#### 6.1 Content type rules

* The Admin API supports **JSON only**:

  * Requests: `Content-Type: application/json` for any request with a body.
  * Responses: `Content-Type: application/json`.
* If a request body is required and the content type is not JSON, respond `415 Unsupported Media Type`.

#### 6.2 Error model

All non-2xx responses must return a JSON object:

```json
{
  "error": "string_code",
  "message": "human readable message",
  "details": {}
}
```

Validation failures must use:

```json
{
  "error": "validation_failed",
  "message": "invalid configuration",
  "details": { "fields": { "field_name": "reason" } }
}
```

---

### 7) JSON Schema Requirements

#### 7.1 Device configuration schema

Each Device Type must publish a JSON Schema describing its `settings` object.

* Must be JSON Schema
* Must mark secrets in a consistent way (see 7.3).
* Must encode validation constraints (required fields, enums, ranges, formats).

#### 7.2 API payload schemas

The provider should publish JSON Schemas for:

* create device request

(At minimum, device configuration schemas for each device type are required)

#### 7.3 Secrets handling

* Settings fields that are secrets must be treated as write-only:

  * GET responses must **redact** secret values (e.g., `null` or `"***redacted***"`).
  * Update requests may omit secret fields to keep existing values unchanged.
  * JSON Schema should indicate secrets (implementation-defined; e.g. `{"writeOnly": true}` or custom annotation).

---

### 8) Required Routes

#### 8.1 Provider info / health

* `GET /`

  * Returns provider info:

    ```json
    {
      "name": "modbus_provider",
      "version": "x.y.z",
      "uptime_seconds": 123,
      "device_types": ["modbus_hvac", "modbus_meter"],
      "counts": { "devices": 3, "healthy": 2, "unhealthy": 1 }
    }
    ```

* `GET /health`

  * Fast status endpoint:

    ```json
    { "status": "ok" }
    ```
  * If degraded/error:

    ```json
    { "status": "degraded", "reasons": ["device:abc unreachable"] }
    ```

#### 8.2 Device types and schemas

* `GET /device-types`

  * Lists supported device types:

    ```json
    {
      "device_types": [
        { "type": "modbus_hvac", "label": "Modbus HVAC" }
      ]
    }
    ```

* `GET /device-types/:type/schema`

  * Returns JSON Schema for that device type’s `settings`.

#### 8.3 Device instances

* `GET /devices`

  * Lists all device instances:

    ```json
    [
      {
        "id": "abc123",
        "type": "modbus_hvac",
        "label": "Level 3 AHU",
        "health": { "status": "ok" }
      }
    ]
    ```

* `POST /devices`

  * Creates a device instance.
  * Request:

    ```json
    {
      "type": "modbus_hvac",
      "label": "Level 3 AHU",
      "settings": { "...": "..." }
    }
    ```
  * Response `201`:

    ```json
    {
      "id": "abc123",
      "type": "modbus_hvac",
      "label": "Level 3 AHU",
      "settings": { "...": "..." }
    }
    ```

* `GET /devices/:id`

  * Returns a device instance record including:

    * redacted settings
    * health
    * a state snapshot suitable for debugging (implementation-defined)
    * endpoints

    ```json
    {
      "id": "abc123",
      "type": "modbus_hvac",
      "label": "Level 3 AHU",
      "settings": { "host": "10.0.0.5", "password": "***redacted***" },
      "health": { "status": "ok", "last_seen_at": "2026-01-31T01:23:45Z" },
      "snapshot": { "...": "..." }
    }
    ```

* `PATCH /devices/:id`

  * Updates label/settings.
  * Request:

    ```json
    {
      "label": "New Name",
      "settings": { "...": "..." }
    }
    ```
  * Secrets omitted from settings must keep existing values.

* `DELETE /devices/:id`

  * Removes the device instance and its bridged endpoints.
  * Response:

    ```json
    { "deleted": true }
    ```

#### 8.4 Device refresh

* `POST /devices/:id/refresh`

  * Triggers immediate refresh/poll and returns updated health + snapshot.

#### 8.5 Bridge commissioning

Commissioning applies to the bridge node itself, not individual devices. Once the bridge is commissioned, all device endpoints are accessible.

* `POST /commission?duration_seconds=900`

  * Opens a commissioning window for the bridge node.
  * Response:

    ```json
    {
      "qr_payload": "MT:....",
      "manual_pairing_code": "34970112345",
      "discriminator": 3840,
      "expires_at": "2026-01-31T02:15:00Z"
    }
    ```

* `GET /commission`

  * Returns commissioning state for the bridge.
  * Includes `commission_info` when commissioning is active (not yet commissioned):

    ```json
    {
      "active": true,
      "commissioned": false,
      "fabric_count": 0,
      "commission_info": {
        "qr_payload": "MT:....",
        "manual_pairing_code": "34970112345",
        "discriminator": 3840
      }
    }
    ```
  * When already commissioned, `commission_info` is `null`.

---

### 9) Endpoint Stability and Unavailability

* Each device instance must have a stable `id` persisted across restarts.
* Device instance `id` → endpoint id(s) mapping must be stable across restarts.
* Temporary unavailability should not cause endpoint renumbering or removal; reflect it in `health` and/or Matter-exposed health/status attributes as appropriate.

---

### 10) Base Library Responsibilities (shared by all providers)

The shared base provider library must supply:

* CLI parsing (`--http`, `--data`, `--bearer`)
* JSON-only HTTP server and routing
* consistent JSON error handling
* JSON Schema hosting for device type configuration
* device registry persistence + endpoint assignment stability
* Matter node lifecycle + fabric persistence
* Log to stdout
* an API for device implementations to:

  * register bridged endpoints/clusters
  * update attributes and emit events
  * expose health state

Provider implementers should only write:

* device types + JSON Schemas
* settings→runtime wiring (connect/poll/subscribe)
* mapping from device state to Matter attributes/commands/events
