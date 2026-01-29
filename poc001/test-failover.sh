#!/bin/bash

set -e

TRACE_ID_COUNTER=1

send_trace() {
    local service_name=$1
    local trace_id=$(printf '%032X' $TRACE_ID_COUNTER)
    local span_id=$(printf '%016X' $TRACE_ID_COUNTER)

    echo "Sending trace: service=$service_name, traceId=$trace_id"

    curl -s -X POST http://localhost:4318/v1/traces \
      -H "Content-Type: application/json" \
      -d "{
        \"resourceSpans\": [{
          \"resource\": {
            \"attributes\": [{
              \"key\": \"service.name\",
              \"value\": {\"stringValue\": \"$service_name\"}
            }]
          },
          \"scopeSpans\": [{
            \"spans\": [{
              \"traceId\": \"$trace_id\",
              \"spanId\": \"$span_id\",
              \"name\": \"test-span\",
              \"kind\": 1,
              \"startTimeUnixNano\": \"$(date +%s)000000000\",
              \"endTimeUnixNano\": \"$(date +%s)000000001\"
            }]
          }]
        }]
      }"

    TRACE_ID_COUNTER=$((TRACE_ID_COUNTER + 1))
    echo ""
}

echo "=========================================="
echo "  OpenTelemetry Failover Connector Test"
echo "=========================================="
echo ""

echo "[1] Starting all collectors..."
docker-compose up -d
sleep 5

echo ""
echo "[2] Sending trace to PRIMARY collector..."
send_trace "test-primary"
sleep 2

echo ""
echo "[3] Checking PRIMARY collector logs..."
docker logs otel-collector-primary 2>&1 | grep -i "test-primary" || echo "No matching logs found yet"

echo ""
echo "[4] Stopping PRIMARY collector..."
docker stop otel-collector-primary
sleep 2

echo ""
echo "[5] Sending trace - should go to SECONDARY..."
send_trace "test-failover"
sleep 2

echo ""
echo "[6] Checking SECONDARY collector logs..."
docker logs otel-collector-secondary 2>&1 | grep -i "test-failover" || echo "No matching logs found yet"

echo ""
echo "[7] Restarting PRIMARY collector..."
docker start otel-collector-primary
echo "Waiting for retry_interval (5s)..."
sleep 7

echo ""
echo "[8] Sending trace - should return to PRIMARY..."
send_trace "test-recovered"
sleep 2

echo ""
echo "[9] Checking PRIMARY collector logs..."
docker logs otel-collector-primary 2>&1 | grep -i "test-recovered" || echo "No matching logs found yet"

echo ""
echo "=========================================="
echo "  Test Complete!"
echo "=========================================="
echo ""
echo "Summary of logs:"
echo ""
echo "=== PRIMARY Collector ==="
docker logs otel-collector-primary 2>&1 | grep -E "(service\.name|Span)" | tail -10 || echo "No relevant logs"

echo ""
echo "=== SECONDARY Collector ==="
docker logs otel-collector-secondary 2>&1 | grep -E "(service\.name|Span)" | tail -10 || echo "No relevant logs"

echo ""
echo "To cleanup: docker-compose down"
