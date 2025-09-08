![logo](logo.svg)

**GELLI** \ˈgel-ē\ ● *proper noun* — *fr Modern English **gel** ("to congeal") fr Old French **gelee** (“to congeal, frost”) fr Latin **gelare** (“to freeze”) fr root **gelū** (“frost”) ● Also known as the acronymn **"General Edge Local Llama Instances"**  — but only in marketing for extreme techno-nerds.*

1. A deep freeze container for AI models without the Amazon rainforest in tow...
2. Especially for use with AI in contrained spaces.
3. Easily train LoRAs on your corpus without fuss.
4. Intended to avoid leakage or other AI security mishaps.

### Compile, quantize, bake, train, import and export AI artifact with the casual flair...

```bash
curl -fsSL https://github.com/frinknet/gelli/raw/main/install.sh | sh
```

Or you can install a different version (even `develop` or `preview`) by adding a version:

```bash
curl -fsSL https://github.com/frinknet/gelli/raw/main/install.sh | sh -s -- $VER
```

Once installed, keeping things up to date is easy by running: (Note you can change version numbers but it defaults to latest)

```bash
gelli update $VER
```

# Managing Models & LoRAs

Internally GELLI manages its own models. It is really meant to be a general purpose runner for just about anything you can think of...

TODO - Write about DL from HF or OL or MR
TODO - write about importting models and loras


# Running your Models

TODO Explain prompt one shot
TODO Explain serve models
TODO Explain using aLoRAs

# Creating Agentic Systems

TODO Explain agent workflow
TODO Explain adding more tools
TODO Explain adding agent memory
TODO Explain adding interfaces
TODO Explain adding endpoints

# Developing your Own Models

TODO - Write about training LoRAs
TODO - Write about testing your LoRA
TODO - Write about merging into base models
TODO - Write about exporting models and loras


