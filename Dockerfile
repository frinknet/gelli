# GELLI - Generic Entrypoint for Llama LoRA Interaction
FROM alpine:latest AS build

# get the basic build-deps
RUN apk add --no-cache build-base cmake git bash curl-dev
WORKDIR /src

# build all binaries (including finetune from examples)
RUN git clone --depth 1 "https://github.com/ggml-org/llama.cpp" .
RUN find . -type f -name "*.cpp" -exec sed -i 's/<linux\/limits.h>/<limits.h>/g' {} +
RUN find . -type f -name "*.c"	 -exec sed -i 's/<linux\/limits.h>/<limits.h>/g' {} +
RUN cmake -B build -DCMAKE_BUILD_TYPE=Release
RUN cmake --build build --config Release -j$(nproc)

# new container to keep it lean 
FROM alpine:latest

# Install runtime dependencies
RUN apk add --no-cache \
    jq \
    libstdc++ \
    libgcc \
    curl \
    && mkdir -p /models /loras /work

# Copy binaries and shared libraries
COPY --from=build /src/build/bin/llama* /usr/local/bin/
COPY --from=build /src/build/src/libllama.so /usr/local/lib/
COPY --from=build /src/build/ggml/src/libggml*.so /usr/local/lib/
COPY tools/* /usr/local/bin/

# Make them executable and update library cache
RUN chmod +x /usr/local/bin/* && ldconfig /usr/local/lib

# Store version
ARG VERSION
RUN test -n "$VERSION" && printf 'GELLI %s\n' "$VERSION" > /etc/VERSION

# overridable defaults
ENV GELLI_PORT=7771 \
	GELLI_CONTEXT= \
	GELLI_MODEL=ol:qwen3:0.6b \
	GELLI_LORAS=

# we're ready to go
WORKDIR /work
ENTRYPOINT ["gelli"]
