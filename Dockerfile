# GELLI - Generic Entrypoint for Llama LoRA Interaction
FROM alpine:latest AS build

# get the basic build-deps
RUN apk add --no-cache build-base cmake git bash curl-dev

WORKDIR /src

# build ALL binaries (including finetune from examples)
RUN git clone --depth 1 "https://github.com/ggml-org/llama.cpp" .
RUN find . -type f -name "*.cpp" -exec sed -i 's/<linux\/limits.h>/<limits.h>/g' {} +
RUN find . -type f -name "*.c"	 -exec sed -i 's/<linux\/limits.h>/<limits.h>/g' {} +
RUN cmake -B build -DCMAKE_BUILD_TYPE=Release
RUN cmake --build build --config Release -j$(nproc)

# new container to keep it lean 
FROM alpine:latest

# install ALL binaries (now includes finetune!)
COPY --from=build /src/build/bin/llama* /usr/local/bin/
COPY tools/* /usr/local/bin/

# make them executable
RUN chmod +x /usr/local/bin/*; \
	mkdir -p /models /loras /work

# overridable defaults
ENV LORAS= \
	MODEL=Qwen/Qwen2.5-0.5B-Instruct \
	PORT=7771

ARG VERSION
RUN test -n "$VERSION" && printf 'GELLI %s\n' "$VERSION" > /etc/VERSION

# we're ready to go
EXPOSE 7771
WORKDIR /work
ENTRYPOINT ["gelli"]
