# Manual: GreenTrustChain — High-level overview

## What this is
A hybrid on-chain/off-chain prototype for “green” energy transactions where an on-chain Solidity contract (GreenTrustChain) records transactions and enforces policy, while an off-chain Python trust engine computes trust scores and benchmarks. It is intended for researchers or developers building energy-market smart contracts with a separate trust-evaluation pipeline and workload/benchmark tests.

### Stack
- **Language(s):** TypeScript (tests / deployment scripts), Solidity (smart contracts), Python (off-chain trust engine / dataset processing)
- **Framework / runtime:** Hardhat (Solidity build/test/deploy) + Node/TypeScript for test/deploy scripts; Python runtime for the trust engine/experiments
- **Notable libraries / tooling:** OpenZeppelin Contracts (used by Solidity contracts), Hardhat (build/test runtime), TypeScript tooling (tsconfig present) — plus typical Hardhat ecosystem tooling (ethers.js / Hardhat Runtime Environment used by the deploy/test scripts).

## How it's organized
Top-level (focused) tree:

```
Trustcode with benchmark/
  GSCROF_benchmark_95556.csv    (large benchmark dataset / workload)
  Greenchain/                   (Solidity contracts: core protocol)
    GreenTrustChain.sol
    GreenTrustChain_modified.sol
    GreenTrustChain_v1_2_0_negative_energy.sol
    DeterministicBaseline.sol
    EnergyAwareBaseline.sol
    TrustOnlyBaseline.sol
  Interfaces/                   (TypeScript + Hardhat config + deploy script)
    hardhat.config.ts
    deploy.ts
    tsconfig.json
  Python/                       (off-chain trust engine, dataset adapter, tests)
    trust_engine.py
    trust_dataset_adapter.py
    dataset_audit.py
    test_trust_engine.py
    trust_config.json
    experiment_manifest.json
  Tests/                        (TypeScript test/benchmark harness & replay)
    GreenTrustChain.ts
    GreenTrustChain.integration.ts
    Baselines.ts
    replay_workload.ts
  experiments/                   (experiment code / notebooks - placeholder)
```

How it fits together:
- Smart-contract layer: `Greenchain/GreenTrustChain.sol` implements transaction submission, validator/governance roles, on-chain storage of transactions and `trustScore` fields, and execution rules (approve/reject) based on assigned verification levels and thresholds.
- Off-chain layer: `Python/trust_engine.py` + `trust_dataset_adapter.py` process the benchmark dataset and produce trust scores for transactions; those scores are intended to be submitted on-chain by validator accounts via `updateTrustScore`.
- Deployment & tests: `Interfaces/deploy.ts` and Hardhat config provide the TypeScript/Hardhat deployment and test harness; `Tests/*.ts` contains workload replays and integration/benchmark tests that simulate transaction submission and validator actions against the contract.

## How to run it
Shortest path (assumes a typical Hardhat + Node + Python environment):

1) Clone the repo
```
git clone https://github.com/profravikhatri/GreenTrustChain.git
cd "GreenTrustChain/Trustcode with benchmark"
```

2) Run Solidity tests / deploy with Hardhat (Interfaces directory)
```
cd "Interfaces"
# install Node deps if a package.json exists
npm install
# run Hardhat tests
npx hardhat test
# run the deploy script locally (adjust network as configured in hardhat.config.ts)
npx hardhat run --network localhost ./deploy.ts
```

3) Run the off-chain trust engine (Python)
```
cd ../Python
# create venv and install dependencies if a requirements file exists
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt   # if present
# run the trust engine or tests
python trust_engine.py
python -m pytest test_trust_engine.py
```

Notes / environment:
- The Solidity contracts import OpenZeppelin; ensure Hardhat can install & compile those (npm install).
- The repository contains a large CSV (`GSCROF_benchmark_95556.csv`) used by the Python code and the Tests harness — ensure you have sufficient disk/memory when running benchmarks.
- There is no top-level README in the inspected tree; check `Interfaces` for `package.json` and `Python` for `requirements.txt` to see exact dependency pins and npm / pip commands.

## Try asking
- Can you show the trust-scoring function in `Python/trust_engine.py` and explain how its output maps to the on-chain `trustScore` and verification thresholds in `Greenchain/GreenTrustChain.sol`?
- What network and account setup does `Interfaces/deploy.ts` expect (check `hardhat.config.ts`) and which accounts are granted GOVERNANCE / VALIDATOR / PARTICIPANT roles by the deploy script?
- How does `Tests/replay_workload.ts` map rows from `GSCROF_benchmark_95556.csv` into `submitTransaction` calls — can you point me to the adapter code in `Python/trust_dataset_adapter.py` or the TypeScript replay code?
