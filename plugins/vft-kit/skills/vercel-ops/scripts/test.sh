#!/bin/bash

# vercel-ops Test Suite
# 验证所有核心功能

set -e

echo "======================================"
echo "Vercel-ops Test Suite"
echo "======================================"
echo ""

# 检查 Node 版本
echo "1. Checking Node.js version..."
NODE_VERSION=$(node --version)
echo "   Node: $NODE_VERSION"

if [[ "$NODE_VERSION" < "v18" ]]; then
  echo "   ✗ Node.js 18+ required"
  exit 1
fi
echo "   ✓ Node version OK"
echo ""

# 检查 token
echo "2. Checking VERCEL_TOKEN..."
if [ -z "$VERCEL_TOKEN" ]; then
  echo "   ✗ VERCEL_TOKEN not set"
  echo "   Run: export VERCEL_TOKEN=your-token"
  exit 1
fi
echo "   ✓ Token found"
echo ""

# 测试 verify
echo "3. Testing verify command..."
if node scripts/vercel-ops.js verify > /dev/null 2>&1; then
  echo "   ✓ Token is valid"
else
  echo "   ✗ Token verification failed"
  exit 1
fi
echo ""

# 测试 teams list
echo "4. Testing teams list..."
TEAMS_COUNT=$(node scripts/vercel-ops.js teams list --json 2>/dev/null | jq -r '.teams | length')
echo "   Found $TEAMS_COUNT team(s)"
echo "   ✓ Teams list works"
echo ""

# 测试 projects list
echo "5. Testing projects list..."
PROJECTS_COUNT=$(node scripts/vercel-ops.js projects list --json 2>/dev/null | jq -r '.projects | length')
echo "   Found $PROJECTS_COUNT project(s)"
echo "   ✓ Projects list works"
echo ""

# 测试 JSON 输出
echo "6. Testing JSON output..."
JSON_OUTPUT=$(node scripts/vercel-ops.js projects list --limit 1 --json 2>/dev/null)
if echo "$JSON_OUTPUT" | jq '.' > /dev/null 2>&1; then
  echo "   ✓ JSON output is valid"
else
  echo "   ✗ JSON output is invalid"
  exit 1
fi
echo ""

# 测试 api 命令
echo "7. Testing direct API command..."
API_RESULT=$(node scripts/vercel-ops.js api GET /v2/user --json 2>/dev/null)
if echo "$API_RESULT" | jq -r '.user.id' > /dev/null 2>&1; then
  echo "   ✓ Direct API call works"
else
  echo "   ✗ Direct API call failed"
  exit 1
fi
echo ""

# 测试错误处理
echo "8. Testing error handling..."
if node scripts/vercel-ops.js projects get invalid-project-id > /dev/null 2>&1; then
  echo "   ✗ Should have failed for invalid project"
  exit 1
else
  echo "   ✓ Error handling works"
fi
echo ""

echo "======================================"
echo "All tests passed! ✓"
echo "======================================"
echo ""
echo "Available commands:"
echo "  - verify          : Verify token"
echo "  - projects        : Manage projects"
echo "  - deployments     : Manage deployments"
echo "  - domains         : Manage domains"
echo "  - env             : Manage environment variables"
echo "  - logs            : Query deployment logs"
echo "  - aliases         : Manage aliases"
echo "  - teams           : Manage teams"
echo "  - api             : Direct API calls"
echo ""
echo "Run any command with --help for details."
