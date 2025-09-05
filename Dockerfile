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
RUN apk add --no-cache jq vim git curl libstdc++ libgomp && \
    mkdir -p /models /loras /work /usr/local/lib

# Set version
ARG VERSION
RUN test -n "$VERSION" && printf 'GELLI %s\n' "$VERSION" > /etc/VERSION
RUN echo 'export PS1="\n\[\e[1;91m\]  \w \[\e[38;5;52m\]\$\[\e[0m\] \[\e]12;#999900\007\]\[\e]12;#999900\007\]\[\e[3 q\]"' > /.env

# Copy ALL binaries in one layer
COPY --from=build /src/build/bin/* /usr/local/bin/

# Copy ALL shared libraries in one layer  
COPY --from=build /src/build/bin/*.so /usr/local/lib/

# Set defaults environment
ENV ENV=/.env \
    GELLI_PORT=7771 \
    GELLI_CTX_SIZE=0 \
    GELLI_DEFAULT=ol:qwen3:0.6b \
    GELLI_MODEL= \
    GELLI_LORAS=

# Ready to rock
WORKDIR /work
ENTRYPOINT ["gelli"]
