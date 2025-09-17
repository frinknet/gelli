# Final lean stage
FROM gelli

# Set version and image name
ARG VERSION
ARG IMAGE

# Add tools directory
COPY . /$IMAGE/

# Wrapper + entrypoint
RUN <<ENTRYBIN

# Version file
printf 'GELLI %s\n' "$VERSION" > "/$IMAGE/VERSION"

# Environment loader
cat > /bin/env <<ENV
#!/usr/bin/env sh
source /$IMAGE/bin/env
ENV

# User-facing CLI wrapper
cat > "/usr/bin/$IMAGE" <<CLI
#!/bin/env sh
${IMAGE}-start "\$@"
CLI

chmod +x /bin/env
chmod +x "/usr/bin/$IMAGE"
ln -sf "/usr/bin/$IMAGE" /bin/entrypoint

ENTRYBIN

# Set default model
ENV ENV=/gelli/bin/env \
GELLI_DEFAULT=ol:qwen3:1.7b

# Ready to rock
WORKDIR /work
ENTRYPOINT ["/bin/entrypoint"]
