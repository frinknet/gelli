# GELLI - General Edge Local Llama Instances
FROM alpine:latest AS build
RUN apk add --no-cache build-base cmake git bash curl-dev

WORKDIR /src

# Get llama source
RUN git clone --depth 1 "https://github.com/ggml-org/llama.cpp" .

# Fix header problem (may cause problems don't know)
RUN find . -type f -name "*.cpp" -exec sed -i 's/<linux\/limits.h>/<limits.h>/g' {} +
RUN find . -type f -name "*.c"	 -exec sed -i 's/<linux\/limits.h>/<limits.h>/g' {} +

# Are the redundant?
RUN cmake -B build -DCMAKE_BUILD_TYPE=Release
RUN cmake --build build --config Release -j$(nproc)

# Add gelli tools
COPY tools/gelli* /src/build/bin/
RUN chmod +x /src/build/bin/*

# Final lean stage
FROM alpine:latest
RUN apk add --no-cache jq && \
    mkdir -p /models /loras /work /usr/local/lib

# Set version
ARG VERSION
RUN test -n "$VERSION" && printf 'GELLI %s\n' "$VERSION" > /etc/VERSION

# Copy ALL binaries in one layer
COPY --from=build /src/build/bin/gelli* /src/build/bin/llama* /usr/local/bin/

# Copy ALL shared libraries in one layer  
COPY --from=build /src/build/bin/*.so /usr/local/lib/

# Set defaults environment
ENV GELLI_PORT=7771 \
    GELLI_CONTEXT= \
    GELLI_MODEL=ol:qwen3:0.6b \
    GELLI_LORAS=

# Ready to rock
WORKDIR /work
ENTRYPOINT ["gelli"]
