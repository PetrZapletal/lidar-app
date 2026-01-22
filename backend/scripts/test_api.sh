#!/bin/bash
# =============================================================================
# LiDAR Backend API Test Script
# =============================================================================
# Tests all main API endpoints via HTTPS
#
# Usage:
#   ./scripts/test_api.sh [HOST] [PORT]
#
# Examples:
#   ./scripts/test_api.sh                          # localhost:8444
#   ./scripts/test_api.sh 100.96.188.18 8444       # Tailscale
# =============================================================================

HOST=${1:-127.0.0.1}
PORT=${2:-8444}
BASE_URL="https://${HOST}:${PORT}"

echo "=============================================="
echo "LiDAR Backend API Test"
echo "=============================================="
echo "Target: ${BASE_URL}"
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

pass() { echo -e "${GREEN}PASS${NC}: $1"; }
fail() { echo -e "${RED}FAIL${NC}: $1"; }

# 1. Health Check
echo "--- 1. Health Check ---"
HEALTH=$(curl -sk "${BASE_URL}/health" 2>/dev/null)
if echo "$HEALTH" | grep -q "healthy"; then
    pass "Health endpoint"
else
    fail "Health endpoint"
    echo "Response: $HEALTH"
fi
echo ""

# 2. Login
echo "--- 2. Login ---"
LOGIN_RESPONSE=$(curl -sk -X POST "${BASE_URL}/api/v1/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"email":"test@test.com","password":"test123"}' 2>/dev/null)

if echo "$LOGIN_RESPONSE" | grep -q "accessToken"; then
    pass "Login endpoint"
    TOKEN=$(echo "$LOGIN_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['tokens']['accessToken'])" 2>/dev/null)
    echo "Token: ${TOKEN:0:50}..."
else
    fail "Login endpoint"
    echo "Response: $LOGIN_RESPONSE"
    exit 1
fi
echo ""

# 3. User Profile
echo "--- 3. User Profile ---"
PROFILE=$(curl -sk "${BASE_URL}/api/v1/users/me" \
    -H "Authorization: Bearer $TOKEN" 2>/dev/null)

if echo "$PROFILE" | grep -q "test-user-1"; then
    pass "User profile endpoint"
else
    fail "User profile endpoint"
    echo "Response: $PROFILE"
fi
echo ""

# 4. Create Scan
echo "--- 4. Create Scan ---"
SCAN_RESPONSE=$(curl -sk -X POST "${BASE_URL}/api/v1/scans" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    -d '{"name":"API Test Scan","device_info":{"model":"TestDevice","os_version":"17.0","has_lidar":true}}' 2>/dev/null)

if echo "$SCAN_RESPONSE" | grep -q '"status":"created"'; then
    pass "Create scan endpoint"
    SCAN_ID=$(echo "$SCAN_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null)
    echo "Scan ID: $SCAN_ID"
else
    fail "Create scan endpoint"
    echo "Response: $SCAN_RESPONSE"
    exit 1
fi
echo ""

# 5. Get Scan Status
echo "--- 5. Get Scan Status ---"
STATUS=$(curl -sk "${BASE_URL}/api/v1/scans/${SCAN_ID}/status" \
    -H "Authorization: Bearer $TOKEN" 2>/dev/null)

if echo "$STATUS" | grep -q "$SCAN_ID"; then
    pass "Get scan status endpoint"
else
    fail "Get scan status endpoint"
    echo "Response: $STATUS"
fi
echo ""

# 6. List Scans
echo "--- 6. List Scans ---"
SCANS=$(curl -sk "${BASE_URL}/api/v1/scans" \
    -H "Authorization: Bearer $TOKEN" 2>/dev/null)

if echo "$SCANS" | grep -q "$SCAN_ID"; then
    pass "List scans endpoint"
else
    fail "List scans endpoint"
    echo "Response: $SCANS"
fi
echo ""

# 7. Delete Scan
echo "--- 7. Delete Scan ---"
DELETE=$(curl -sk -X DELETE "${BASE_URL}/api/v1/scans/${SCAN_ID}" \
    -H "Authorization: Bearer $TOKEN" 2>/dev/null)

if echo "$DELETE" | grep -q "deleted"; then
    pass "Delete scan endpoint"
else
    fail "Delete scan endpoint"
    echo "Response: $DELETE"
fi
echo ""

# 8. WebSocket (basic check)
echo "--- 8. WebSocket Check ---"
WS_CHECK=$(curl -sk -o /dev/null -w "%{http_code}" "${BASE_URL}/ws" \
    -H "Upgrade: websocket" -H "Connection: Upgrade" 2>/dev/null)

if [ "$WS_CHECK" = "426" ] || [ "$WS_CHECK" = "101" ]; then
    pass "WebSocket endpoint accessible"
else
    echo "WebSocket response: $WS_CHECK (expected 426 or 101)"
fi
echo ""

echo "=============================================="
echo "API Test Complete"
echo "=============================================="
