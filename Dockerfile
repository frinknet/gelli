# syntax=docker/dockerfile:1
# GELLI - General Edge Local Llama Instances
FROM alpine:latest AS build
RUN apk add --no-cache \
  build-base cmake git bash curl-dev \
  vulkan-loader-dev vulkan-headers shaderc glslang spirv-tools

WORKDIR /src

# Get llama source
RUN git clone --depth 1 "https://github.com/ggml-org/llama.cpp" .

# Fix header problem (may cause problems don't know)
RUN find . -type f -name "*.cpp" -exec sed -i 's/<linux\/limits.h>/<limits.h>/g' {} +
RUN find . -type f -name "*.c"	 -exec sed -i 's/<linux\/limits.h>/<limits.h>/g' {} +

# Drop optimization just for ggml-vulkan big files to reduce cc1plus RAM
RUN sed -i 's@add_library(ggml-vulkan@set_source_files_properties(ggml/src/ggml-vulkan/ggml-vulkan.cpp PROPERTIES COMPILE_OPTIONS "-O1")\nset_source_files_properties(ggml/src/ggml-vulkan/ggml-vulkan-shaders.cpp PROPERTIES COMPILE_OPTIONS "-O1")\n&@' ggml/CMakeLists.txt

# glslc shim: replace a standalone "-O" with "-O0" and preserve all args
RUN cat > /usr/local/bin/glslc <<'SH' && chmod +x /usr/local/bin/glslc
#!/bin/sh
set -e

new=''

while [ "$#" -gt 0 ]; do
  if [ "$1" = "-O" ]; then
    arg='-O0'
  else
    arg="$1"
  fi

  new="$new '$(printf "%s" "$arg" | sed "s/'/'\"'\"'/g")'"

  shift
done

# shellcheck disable=SC2086
eval "set -- $new"

exec /usr/bin/glslc "$@"
SH

# Build for all linux headers
RUN cmake -B build \
  -DGGML_CUBLAS=ON \
  -DGGML_CLBLAST=ON \
  -DGGML_HIPBLAS=ON \
  -DGGML_VULKAN=ON \
  -DCMAKE_CUDA_ARCHITECTURES=all-major \
  -DLLAMA_NATIVE=OFF \
  -DLLAMA_BUILD_TESTS=OFF \
  -DLLAMA_BUILD_EXAMPLES=ON \
  -DCMAKE_CXX_FLAGS_RELEASE="-O2" \
  -DVulkan_GLSLC_EXECUTABLE=/usr/local/bin/glslc \
  -DCMAKE_BUILD_TYPE=Release

RUN cmake --build build --config Release -j$(nproc)

# Final lean stage
FROM alpine:latest

# Set version and image name
ARG VERSION
ARG IMAGE

# Copy ALL binaries in one layer
COPY --from=build /src/build/bin/llama* /usr/local/bin/

# Copy ALL shared libraries in one layer  
COPY --from=build /src/build/bin/*.so /usr/local/lib/

RUN apk add --no-cache \
  jq vim git curl libstdc++ libgomp \
  vulkan-loader mesa-vulkan-layers vulkan-tools \
  mesa-vulkan-intel mesa-vulkan-ati mesa-vulkan-swrast


RUN mkdir -p /models /loras /work /tools /usr/local/lib \
 && curl -sSLo /usr/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 \
 && chmod +x /usr/bin/yq

# Add tools directory
COPY . /$IMAGE/

# Wrapper + entrypoint
RUN <<ENTRYBIN

# Version file
printf 'GELLI %s\n' "$VERSION" > "$APPDIR/VERSION"

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
