#!/bin/bash
# create-traefik-service.sh
# Run this on dokploy-server (manager node) after Dokploy is installed

set -e

echo "=== Creating Traefik as Docker Swarm Service ==="

# Configuration
MANAGER_TAILSCALE_IP="100.86.130.70"
TRAEFIK_VERSION="v3.6.2"  # Latest stable version

# Create required directories for Traefik configuration
sudo mkdir -p /etc/dokploy/traefik/dynamic

# Create Traefik configuration file
sudo cat > /etc/dokploy/traefik/traefik.yml <<'EOF'
# Traefik Configuration for Dokploy
api:
  dashboard: true
  debug: true

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true
  websecure:
    address: ":443"

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    swarmMode: true
    exposedByDefault: false
    network: dokploy-network
  file:
    directory: /etc/dokploy/traefik/dynamic
    watch: true

certificatesResolvers:
  letsencrypt:
    acme:
      email: jaikhlang@gmail.com  # CHANGE THIS
      storage: /etc/dokploy/traefik/acme.json
      httpChallenge:
        entryPoint: web
      # Staging server for testing (remove for production)
      # caServer: https://acme-staging-v02.api.letsencrypt.org/directory
EOF

# Set proper permissions for acme.json (must be 600 for Traefik)
sudo touch /etc/dokploy/traefik/acme.json
sudo chmod 600 /etc/dokploy/traefik/acme.json

# Create a sample dynamic configuration file
sudo cat > /etc/dokploy/traefik/dynamic/middlewares.yml <<'EOF'
# Custom middlewares for Dokploy
http:
  middlewares:
    secure-headers:
      headers:
        frameDeny: true
        sslRedirect: true
        browserXssFilter: true
        contentTypeNosniff: true
        forceSTSHeader: true
        stsIncludeSubdomains: true
        stsPreload: true
        stsSeconds: 31536000

    rate-limit:
      rateLimit:
        average: 100
        burst: 50

    compression:
      compress:
        excludedContentTypes:
          - text/event-stream
EOF

# Remove existing Traefik container if running (from Docker run method)
sudo docker rm -f dokploy-traefik 2>/dev/null || true

# Create Traefik as Docker Swarm service
sudo docker service create \
  --name dokploy-traefik \
  --constraint 'node.hostname == dokploy-server'\
  --network dokploy-network \
  --mount type=bind,source=/etc/dokploy/traefik/traefik.yml,target=/etc/traefik/traefik.yml \
  --mount type=bind,source=/etc/dokploy/traefik/dynamic,target=/etc/traefik/dynamic \
  --mount type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock \
  --mount type=bind,source=/etc/dokploy/traefik/acme.json,target=/etc/traefik/acme.json \
  --publish mode=host,published=80,target=80 \
  --publish mode=host,published=443,target=443 \
  --publish mode=host,published=443,target=443,protocol=udp \
  --label "traefik.enable=true" \
  --label "traefik.http.routers.traefik.entrypoints=websecure" \
  --label "traefik.http.routers.traefik.rule=Host(\`dokploy.jaikhlang.me\`)" \
  --label "traefik.http.routers.traefik.service=api@internal" \
  --label "traefik.http.routers.traefik.middlewares=secure-headers" \
  --label "traefik.http.routers.traefik.tls.certresolver=letsencrypt" \
  traefik:${TRAEFIK_VERSION}

# Wait for service to be ready
echo "Waiting for Traefik service to start..."
sleep 10

# Verify the service is running
if sudo docker service ps dokploy-traefik --format "table {{.Name}}\t{{.Status}}" | grep -q "Running"; then
    echo "✅ Traefik service is running!"
else
    echo "❌ Traefik service failed to start"
    sudo docker service ps dokploy-traefik
    exit 1
fi

# Get service details
echo ""
echo "=== Traefik Service Status ==="
sudo docker service ls --filter name=dokploy-traefik

echo ""
echo "=== Traefik Service Details ==="
sudo docker service inspect dokploy-traefik --format "{{.Spec.TaskTemplate.ContainerSpec.Image}}"

echo ""
echo "=== Traefik Configuration ==="
echo "Traefik version: ${TRAEFIK_VERSION}"
echo "Config location: /etc/dokploy/traefik/traefik.yml"
echo "Dynamic config: /etc/dokploy/traefik/dynamic/"
echo ""

echo "=== Next Steps ==="
echo "1. Update the email in /etc/dokploy/traefik/traefik.yml for Let's Encrypt"
echo "2. Update the Traefik dashboard domain with your actual domain"
echo "3. To reload Traefik after configuration changes:"
echo "   sudo docker service update --force dokploy-traefik"
echo ""
echo "4. Check Traefik logs:"
echo "   sudo docker service logs dokploy-traefik"