# GELLI - Generic Entrypoint for Llama LoRA Interaction
FROM alpine:latest AS build

# get the basic build-deps
RUN apk add --no-cache build-base cmake git  curl-dev

WORKDIR /src

# build ALL binaries (including finetune from examples)
RUN git clone --depth 1 "https://github.com/ggml-org/llama.cpp" .
RUN cmake -B build -DCMAKE_BUILD_TYPE=Release
RUN cmake --build build --config Release -j$(nproc)
RUN mv build/finetune build/llama-finetune

# new container to keep it lean 
FROM alpine:latest

# install ALL binaries (now includes finetune!)
COPY --from=build /src/build/bin/* /usr/local/bin/
COPY scripts/* /usr/local/bin/

# make them executable
RUN chmod +x /usr/local/bin/*; \
	mkdir -p /models /loras /work

# overridable defaults
ENV LORAS= \
	MODEL=/models/qwen2.5-0.5B.gguf \
	PORT=7771

ARG VERSION
RUN test -n "$VERSION" && printf 'GELLI %s\n' "$VERSION" > /etc/VERSION

# we're ready to go
EXPOSE 7771
WORKDIR /work
ENTRYPOINT ["gelli"]
