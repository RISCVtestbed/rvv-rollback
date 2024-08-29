## Introduction

RVV-rollback is a simple script to translate assembly source code for RISC-V Vector (RVV) Extension [v1.0](https://github.com/riscv/riscv-v-spec/blob/3570f998903f00352552b670f1f7b7334f0a144a/v-spec.adoc) to [v0.7.1](https://github.com/riscv/riscv-v-spec/blob/0a24d0f61b5cd3f1f9265e8c40ab211daa865ede/v-spec.adoc) . This is useful for users wanting to compile code with an upstream compiler which generates code for the ratified v1.0 standard (e.g. `clang >= 14.0`, or `riscv-gnu-toolchain` rvv-next branch), and run on hardware adopting the v0.7.1 standard (e.g. T-Head C906).

This is tested for the following workflow:
1. Clang 15.0 to compile .cpp source to RVV 1.0 `.s`
2. RVV-rollback to translate RVV1.0 `.s` to RVV0.7 `.s`
3. GCC 10.2 (Xuantie-900 linux-5.10.4 glibc gcc Toolchain V2.6.1 B-20220906) to assemble RVV0.7 `.s` to `.o`


## Prerequisites

To use this python tool we recommend installing the following:

1. `clang` with RISC-V support. This requires building a riscv-gnu-toolchain first, and [this PR](https://github.com/riscv-collab/riscv-gnu-toolchain/pull/1166) provides the easiest path to build them together;
2. `gcc` with RVV 0.7 support. Upstream GNU toolchain does not support this; a few older/custom toolchains do provide support. We recommend using `gcc 10.2` from <https://occ.t-head.cn/community/download?id=4090445921563774976>. This version supports both RVV0.7 and RVV1.0, and can be switched with the flag `-march=rv64gcv0p7` or `-march=rv64gcv1p0`.


Other toolchains which support RVV0.7:

- <https://github.com/brucehoult/riscv-gnu-toolchain/tree/rvv-0.7.1> is a clone of the deprecated rvv-0.7.1 branch of the riscv-gnu-toolchain
- <https://occ.t-head.cn/community/download?id=3927429448189939712> is a gcc8.4 toolchain supplied for C9XX CPU. From testing it has superior auto-vectorization performance when run on C906 hardware, and provides good comparison for other compilers.

These toolchains are available for download on the [Edinburgh University DataShare site](https://datashare.ed.ac.uk/handle/10283/4835), and are installed on the login nodes of the [EPCC RISC-V testbed](http://riscv.epcc.ed.ac.uk/).



## Usage
The first step is to compile the CPP file into RVV1.0 assembly:
```
$ <riscv-toolchain-installdir>/bin/clang++ -no-integrated-as -march=rv64gcv  -menable-experimental-extensions -mllvm --riscv-v-vector-bits-min=128 -O3 -S -o <filename.s> -c <inputfile.cpp>
```

- `-no-ingrated-as` turns off the integrated assembler and ensures we can use the gnu assembler in the subsequent step.
- `-march=rv64gcv  -menable-experimental-extensions -mllvm --riscv-v-vector-bits-min=128 -O3`: these flags turn on auto-vectorization. To force the code to emit only 32 bit element for vectors (which is the maximum for the C906 CPU), `v` can be replaced by `zve32f`, which is a subset of the `V` extension supporting element size up to 32-bit for embedded processors. However this might reduce the vectorization.
  

Next we use the `rvv-rollback.py` tool to translate the RVV1.0 assembly to RVV0.7 assembly
```
$ python3 rvv-rollback.py <filename.s> (optional: -o <outfilename.s>) (optional: -v)
```

- This script also changes the `arch` attribute of the assembly to `XXX_v0p7`.
- Given the input `<filename.s>` the default output name will be `<filename-rvv0p7.s>` unless the optional `<outfilename.s>` argument is provided.
- Including the verbosity flag `-v` will print out the changed lines.


Finally we can use the gnu assembler to output to binary 
```
$ <riscv-toolchain-installdir>/bin/riscv64-unknown-linux-gnu-g++ -march=rv64gcv0p7 -O3 -c <filename-rvv0p7.s> -o <outputfile.o>
```



Note:
For larger libraries, the following flags can be useful:
   - CXX flag: `-save-temps` saves the intermediate files including a `.s` assembly, which can then be used for steps 2 & 3 from above.
   - CMAKE flag: `-DCMAKE_VERBOSE_MAKEFILE:BOOL=ON` (or `cmake ...; make VERBOSE=1 -j<n>`) will output explicitly the commands during make, which can be used to obtain all the flags for compilation.

## Limitations
RVV1.0 provides new features that are not available in RVV0.7, and there are instructions which are not translated in this version of the tool. These include and are not limited to:
- `LMUL < 1`
- 64-bit elements


We do not provide any guarantee that this tool will work, and we also do not guarantee the correctness of the result from using this tool.


## RAJAPerf Workflow
RAJAPerf is a performance benchmark suite that uses RAJA, a C++ library for array-based programming. It contains a number of kernels that can be used to test the performance of a compiler. As Clang only supports RVV 1.0, we can use this workflow to aid the iterative enhancement of the rollback tool as the benchmark suite provides performance and correctness metrics. The workflow is separated into two stages.

### Stage 1: Prepare environment
First, we need to build Clang for generation of RVV 1.0 assembly, and we also need a GCC toolchain that supports RVV 0.7.1. 

```bash
$ ./scripts/prepare-env.sh
```

This builds Clang-18.1.8 and GCC-10.4.

### Stage 2: Compile RAJAPerf

Then, run the following script to compile RAJAPerf.

```bash
$ ./scripts/build-raja.sh
```

The script does the following:
1. Create a RAJAPerf build1 that is built with GCC-10.4.
2. Create a RAJAPerf build2 that is built with Clang-18.1.8 using the `--save-temps` flag to save the intermediate assembly files.
3. Use rollback tool on all the `.s` assembly files in build2 to rollback to RVV 0.7.1 (some rollback may fail).
4. Select the `.s` files that have been successfully rolled back and use GCC-10.4 to compile them to `.o` object files (again, some compilation may fail).
5. Select the `.o` files that have been successfully compiled and replace the corresponding `.o` files in build1.
6. Remove all the `.a` static libraries in build1 and rebuild them with the new `.o` files including a mixture of RVV 0.7.1 and rolled back RVV 1.0 object files.
7. Remove the existing RAJAPerf executable in build1 and rebuild it with the new static libraries.

The final RAJAPerf executable will be located in `./RAJAPerf/build-gcc/bin/raja-perf.exe`.

Several log files are generated in the `./build-logs` directory:
- `gcc-build.log`: contains the output of the GCC-10.4 build.
- `llvm-build.log`: contains the output of the Clang-18.1.8 build.
- `compile.log`: contains the output of the rollback, compilation, and linking stages.
- `chaged_and_compiled.log`: contains the list of `.s` files that have been successfully rolled back, compiled, and **made changes**.
- `changed_and_failed.log`: contains the list of `.s` files that have been successfully rolled back, **made changes**, but failed to compile.

> Note: although some kernels have been successfully rolled back and compiled, they may produce `segmentation fault` errors when running the kernel in RAJAPerf. This may due to bugs in the rollback tool where registers accessing value at incorrect addresses which need to be fixed.