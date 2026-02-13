#!/bin/bash
# =============================================================================
# ngrok Tunnel for DefectDojo
# =============================================================================
# This script starts an ngrok tunnel to expose your local DefectDojo instance
# so that GitHub Actions can reach it during CI/CD pipeline runs.
#
# Prerequisites:
#   1. Install ngrok: https://ngrok.com/download
#   2. Sign up for a free ngrok account: https://dashboard.ngrok.com/signup
#   3. Authenticate: ngrok config add-authtoken <YOUR_AUTHTOKEN>
#   4. (Recommended) Claim a free static domain at:
#      https://dashboard.ngrok.com/domains
#
# Usage:
#   ./start-ngrok-defectdojo.sh                  # Uses default port 8080
#   ./start-ngrok-defectdojo.sh 8443             # Custom port
#   ./start-ngrok-defectdojo.sh 8080 my-sub.ngrok-free.app  # With static domain
#
# After starting:
#   Set these GitHub Secrets in your repository:
#     DEFECTDOJO_URL       = https://<your-ngrok-url>
#     DEFECTDOJO_API_TOKEN = <your DefectDojo API token>
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

DEFECTDOJO_PORT="${1:-8080}"
NGROK_DOMAIN="${2:-}"

# Check if ngrok is installed
if ! command -v ngrok &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} ngrok is not installed."
    echo "Install it from: https://ngrok.com/download"
    echo "  Linux:   sudo snap install ngrok"
    echo "  macOS:   brew install ngrok"
    echo "  Manual:  https://ngrok.com/download"
    exit 1
fi

# Check if DefectDojo is running
echo -e "${CYAN}[INFO]${NC} Checking if DefectDojo is running on port ${DEFECTDOJO_PORT}..."
if curl -sf "http://localhost:${DEFECTDOJO_PORT}/api/v2/" > /dev/null 2>&1 || \
   curl -sf "http://localhost:${DEFECTDOJO_PORT}" > /dev/null 2>&1; then
    echo -e "${GREEN}[OK]${NC} DefectDojo is running on port ${DEFECTDOJO_PORT}"
else
    echo -e "${YELLOW}[WARN]${NC} Cannot reach DefectDojo at http://localhost:${DEFECTDOJO_PORT}"
    echo "Make sure DefectDojo is running (docker compose up -d)"
    echo "Continuing anyway..."
fi

# Build ngrok command
NGROK_CMD="ngrok http ${DEFECTDOJO_PORT}"
if [ -n "${NGROK_DOMAIN}" ]; then
    NGROK_CMD="ngrok http --domain=${NGROK_DOMAIN} ${DEFECTDOJO_PORT}"
    echo -e "${CYAN}[INFO]${NC} Using static domain: ${NGROK_DOMAIN}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN} Starting ngrok tunnel${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${CYAN}Local:${NC}  http://localhost:${DEFECTDOJO_PORT}"
if [ -n "${NGROK_DOMAIN}" ]; then
    echo -e "${CYAN}Public:${NC} https://${NGROK_DOMAIN}"
    echo ""
    echo -e "${YELLOW}Set this as your GitHub Secret:${NC}"
    echo -e "  DEFECTDOJO_URL = https://${NGROK_DOMAIN}"
else
    echo -e "${CYAN}Public:${NC} Check ngrok dashboard or terminal output for the URL"
    echo ""
    echo -e "${YELLOW}After ngrok starts, set the public URL as your GitHub Secret:${NC}"
    echo -e "  DEFECTDOJO_URL = https://<random-id>.ngrok-free.app"
fi
echo ""
echo -e "${YELLOW}Tip:${NC} Get a free static domain at https://dashboard.ngrok.com/domains"
echo -e "${YELLOW}     so the URL doesn't change between restarts.${NC}"
echo ""
echo -e "Press Ctrl+C to stop the tunnel."
echo ""

# Start ngrok
exec ${NGROK_CMD}
