# Legal & Technical Disclaimer

**BLA (`bla-agents` — Blind LLM Agents)** is a **defensive** software-engineering and intellectual-property protection toolkit. It is intended for software authors, independent developers, and security researchers to protect **their own** first-party software artifacts against automated AI reverse-engineering pipelines such as REA.

## 1. Defensive use only — protect your own software

You may only run BLA on software, bundles, models, and binaries that **you own** or have **explicit authorization** to modify and distribute. BLA is **not** a tool for attacking, probing, or reverse-engineering third-party software you do not control.

Protective payloads (decoy metadata, honey tables, nesting breakers, canary credentials, synthetic diagnostics) are inert under normal application execution. They are designed to activate **only when an automated reverse-engineering / inspection pipeline** reads the protected artifact — not when your users run the product.

## 2. Benign structures only

All artifacts generated or modified by BLA contain strictly benign, inert software-protection structures:

- Number-theoretic opaque predicates ($O(1)$ arithmetic invariants at runtime)
- Inert synthetic state-machine functions and decoy cross-references
- Decoy architectural metadata (simulated TEE/SGX enclave manifests, honey VLQ source maps, synthetic compiler commit strings)
- Format-valid canary / diagnostic metadata that preserves original runtime behavior

BLA **never** injects destructive commands, shell payloads, network callbacks, or exploitative code into protected binaries or scripts.

## 3. Always verify before shipping

Always verify protected artifacts in your staging environment (`bla verify <protected> <original>` or the defend/harden pipeline) before shipping to production. Confirm runtime equivalence for your own workloads.

## 4. Defense-in-depth — not absolute secrecy

While BLA deterministically trips many static, semantic, and metadata resource caps of automated reverse-engineering agents (such as REA), **no client-side protection scheme can guarantee absolute mathematical secrecy** against a dedicated human analyst with unlimited time and hardware debugging access. Keep high-value secrets (private API keys, master signing keys) on trusted server infrastructure.
