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
RUN chmod +x /src/build/bin/*

# Final lean stage
FROM alpine:latest
# Copy ALL binaries in one layer
COPY --from=build /src/build/bin/llama* /usr/local/bin/

# Copy ALL shared libraries in one layer  
COPY --from=build /src/build/bin/*.so /usr/local/lib/

RUN apk add --no-cache jq vim git curl libstdc++ libgomp && \
    mkdir -p /models /loras /work /tools /usr/local/lib

# Add tools directory
COPY . /gelli/

# Set version
ARG VERSION
RUN printf 'GELLI %s\n' "$VERSION" > /gelli/VERSION; \
    printf '#!/gelli/bin/env sh\ngelli-start "$@"' > /usr/bin/gelli; \
    chmod +x /usr/bin/gelli

# Set default model
ENV ENV=/gelli/bin/env \
GELLI_DEFAULT=ol:qwen3:1.5b

# Ready to rock
WORKDIR /work
ENTRYPOINT ["gelli"]
