# POC001 - Failover Connector

This POC demonstrates the **failover connector** feature of OpenTelemetry Collector Contrib.

## Architecture

```
                                    ┌─────────────────────────┐
                                    │  otel-collector-primary │
                                    │      (Priority 1)       │
                          ┌────────►│      Port: 4327         │
                          │         └─────────────────────────┘
┌─────────────────────────┤
│  otel-collector-main    │ Failover
│  (with failover conn)   │ Connector
│  Ports: 4317, 4318      │
└─────────────────────────┤
                          │         ┌─────────────────────────┐
                          │         │ otel-collector-secondary│
                          └────────►│      (Priority 2)       │
                                    │      Port: 4337         │
                                    └─────────────────────────┘
```

## How It Works

1. The main collector receives telemetry data (traces, metrics, logs) via OTLP
2. The failover connector routes data to the **primary** collector first
3. If the primary collector fails, traffic automatically switches to the **secondary** collector
4. The connector periodically retries the primary (every 5s) to restore the original routing

## Prerequisites

- Docker
- Docker Compose

## Usage

### Start all collectors

```bash
docker-compose up -d
```

### Send test data

Using `curl` to send a trace:

```bash
curl -X POST http://localhost:4318/v1/traces \
  -H "Content-Type: application/json" \
  -d '{
    "resourceSpans": [{
      "resource": {
        "attributes": [{
          "key": "service.name",
          "value": {"stringValue": "test-service"}
        }]
      },
      "scopeSpans": [{
        "spans": [{
          "traceId": "5B8EFFF798038103D269B633813FC60C",
          "spanId": "EEE19B7EC3C1B174",
          "name": "test-span",
          "kind": 1,
          "startTimeUnixNano": "1544712660000000000",
          "endTimeUnixNano": "1544712661000000000"
        }]
      }]
    }]
  }'
```

### View logs to see which collector receives data

```bash
# Primary collector logs
docker logs -f otel-collector-primary

# Secondary collector logs
docker logs -f otel-collector-secondary

# Main collector logs
docker logs -f otel-collector-main
```

## Testing Failover

### 1. Initial state - Primary receives data

```bash
# Send data and check primary logs
docker logs otel-collector-primary 2>&1 | tail -20
```

### 2. Stop the primary collector

```bash
docker stop otel-collector-primary
```

### 3. Send more data - Secondary should now receive it

```bash
# Send another trace
curl -X POST http://localhost:4318/v1/traces \
  -H "Content-Type: application/json" \
  -d '{
    "resourceSpans": [{
      "resource": {
        "attributes": [{
          "key": "service.name",
          "value": {"stringValue": "test-service-failover"}
        }]
      },
      "scopeSpans": [{
        "spans": [{
          "traceId": "6B8EFFF798038103D269B633813FC60D",
          "spanId": "FFF19B7EC3C1B175",
          "name": "failover-test-span",
          "kind": 1,
          "startTimeUnixNano": "1544712662000000000",
          "endTimeUnixNano": "1544712663000000000"
        }]
      }]
    }]
  }'

# Check secondary collector logs
docker logs otel-collector-secondary 2>&1 | tail -20
```

### 4. Restart primary - Traffic should return to primary

```bash
docker start otel-collector-primary

# Wait for retry_interval (5s) and send more data
sleep 6

curl -X POST http://localhost:4318/v1/traces \
  -H "Content-Type: application/json" \
  -d '{
    "resourceSpans": [{
      "resource": {
        "attributes": [{
          "key": "service.name",
          "value": {"stringValue": "test-service-recovered"}
        }]
      },
      "scopeSpans": [{
        "spans": [{
          "traceId": "7B8EFFF798038103D269B633813FC60E",
          "spanId": "AAA19B7EC3C1B176",
          "name": "recovered-test-span",
          "kind": 1,
          "startTimeUnixNano": "1544712664000000000",
          "endTimeUnixNano": "1544712665000000000"
        }]
      }]
    }]
  }'

# Check primary collector logs
docker logs otel-collector-primary 2>&1 | tail -20
```

## Cleanup

```bash
docker-compose down
```

## Configuration Details

### Failover Connector Settings

| Parameter | Value | Description |
|-----------|-------|-------------|
| `priority_levels` | 2 levels | Primary and Secondary pipelines |
| `retry_interval` | 5s | How often to retry higher priority levels |

### Important Notes

- `sending_queue.enabled: false` and `retry_on_failure.enabled: false` are set on exporters to make failover faster
- Without these settings, the collector would buffer and retry, delaying the failover detection

## References

- [Failover Connector Documentation](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/connector/failoverconnector)
- [OpenTelemetry Collector Connectors](https://opentelemetry.io/docs/collector/components/connector/)
