#!/bin/sh
set -e

CONFIG_FILE="${APP_HOME}/config.yaml"

# Priority 1: Use USERNAME/PASSWORD if both are provided
if [ -n "${USERNAME}" ] && [ -n "${PASSWORD}" ]; then
  echo "--- Basic auth enabled: Creating config.yaml with provided credentials. ---"
  
  cat <<EOT > ${CONFIG_FILE}
dataRoot: ./data
listen: true
listenAddress:
  ipv4: 0.0.0.0
  ipv6: '[::]'
protocol:
    ipv4: true
    ipv6: false
dnsPreferIPv6: false
autorunHostname: "auto"
port: 8000
autorunPortOverride: -1
ssl:
  enabled: false
  certPath: "./certs/cert.pem"
  keyPath: "./certs/privkey.pem"
whitelistMode: false
enableForwardedWhitelist: false
whitelist:
  - ::1
  - 127.0.0.1
whitelistDockerHosts: true
basicAuthMode: true
basicAuthUser:
  username: "${USERNAME}"
  password: "${PASSWORD}"
enableCorsProxy: false
requestProxy:
  enabled: false
  url: "socks5://username:password@example.com:1080"
  bypass:
    - localhost
    - 127.0.0.1
enableUserAccounts: false
enableDiscreetLogin: false
autheliaAuth: false
perUserBasicAuth: false
sessionTimeout: -1
disableCsrfProtection: false
securityOverride: false
logging:
  enableAccessLog: true
  minLogLevel: 0
rateLimiting:
  preferRealIpHeader: false
autorun: false
avoidLocalhost: false
backups:
  common:
    numberOfBackups: 50
  chat:
    enabled: true
    checkIntegrity: true
    maxTotalBackups: -1
    throttleInterval: 10000
thumbnails:
  enabled: true
  format: "jpg"
  quality: 95
  dimensions: { 'bg': [160, 90], 'avatar': [96, 144] }
performance:
  lazyLoadCharacters: false
  memoryCacheCapacity: '100mb'
  useDiskCache: true
allowKeysExposure: true
skipContentCheck: false
whitelistImportDomains:
  - localhost
  - cdn.discordapp.com
  - files.catbox.moe
  - raw.githubusercontent.com
requestOverrides: []
extensions:
  enabled: true
  autoUpdate: false
  models:
    autoDownload: true
    classification: Cohee/distilbert-base-uncased-go-emotions-onnx
    captioning: Xenova/vit-gpt2-image-captioning
    embedding: Cohee/jina-embeddings-v2-base-en
    speechToText: Xenova/whisper-small
    textToSpeech: Xenova/speecht5_tts
enableDownloadableTokenizers: true
promptPlaceholder: "[Start a new chat]"
openai:
  randomizeUserId: false
  captionSystemPrompt: ""
deepl:
  formality: default
mistral:
  enablePrefix: false
ollama:
  keepAlive: -1
  batchSize: -1
claude:
  enableSystemPromptCache: false
  cachingAtDepth: -1
enableServerPlugins: true
enableServerPluginsAutoUpdate: false
EOT

# Priority 2: Use CONFIG_YAML if provided (and username/password are not)
elif [ -n "${CONFIG_YAML}" ]; then
  echo "--- Found CONFIG_YAML, creating config.yaml from environment variable. ---"
  echo "${CONFIG_YAML}" | base64 -d > ${CONFIG_FILE}

# Priority 3: No config provided, let the app use its defaults
else
    echo "--- No user/pass or CONFIG_YAML provided. App will use its default settings. ---"
fi

echo "*** Starting SillyTavern... ***"
node ${APP_HOME}/server.js &
SERVER_PID=$!

echo "SillyTavern server started with PID ${SERVER_PID}. Waiting for it to become responsive..."

# --- Health Check Logic ---
HEALTH_CHECK_URL="http://localhost:8000/"
CURL_COMMAND="curl -sf"

# If basic auth is enabled, provide credentials to curl for health checks
if [ -n "${USERNAME}" ] && [ -n "${PASSWORD}" ]; then
    echo "--- Health check will use basic auth credentials. ---"
    # The -u flag provides user:password for basic auth
    CURL_COMMAND="curl -sf -u \"${USERNAME}:${PASSWORD}\""
fi

# Health check loop
RETRY_COUNT=0
MAX_RETRIES=12 # Wait for 60 seconds max
# Use eval to correctly execute the command string with quotes
while ! eval "${CURL_COMMAND} ${HEALTH_CHECK_URL}" > /dev/null; do
    RETRY_COUNT=$((RETRY_COUNT+1))
    if [ ${RETRY_COUNT} -ge ${MAX_RETRIES} ]; then
        echo "SillyTavern failed to start. Exiting."
        kill ${SERVER_PID}
        exit 1
    fi
    echo "SillyTavern is still starting or not responsive on port 8000, waiting 5 seconds..."
    sleep 5
done

echo "SillyTavern started successfully! Beginning periodic keep-alive..."

# Keep-alive loop
while kill -0 ${SERVER_PID} 2>/dev/null; do
    echo "Sending keep-alive request to ${HEALTH_CHECK_URL}"
    # Use eval here as well for the keep-alive command
    eval "${CURL_COMMAND} ${HEALTH_CHECK_URL}" > /dev/null || echo "Keep-alive request failed."
    echo "Keep-alive request sent. Sleeping for 30 minutes."
    sleep 1800
done &

wait ${SERVER_PID} 