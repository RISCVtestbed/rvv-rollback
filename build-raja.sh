#!/bin/bash

git submodule update --init --recursive
cd RAJAPerf

source /home/s2551341/work/s2551341/test/llvm-omp-env.sh 18
src_dir=$(pwd)
echo $src_dir
gcc_build_dir=build-gcc
llvm_build_dir=build-llvm
rm -rf rollback.log \
       compile.log \
       llvm-build.log \
       gcc-build.log


###########################
###########################
###########################


rm -rf $llvm_build_dir
mkdir $llvm_build_dir
cd $llvm_build_dir
pwd
echo "Building with RAJAPerf using Clang..."
cmake -DCMAKE_C_COMPILER=clang \
      -DCMAKE_CXX_COMPILER=clang++ \
      -DCMAKE_C_FLAGS="-no-integrated-as -g -march=rv64gcv -mllvm --riscv-v-vector-bits-min=128 -O3 -save-temps" \
      -DCMAKE_CXX_FLAGS="-no-integrated-as -g -march=rv64gcv -mllvm --riscv-v-vector-bits-min=128 -O3 -save-temps" \
      -DENABLE_OPENMP=Off \
      .. >> $src_dir/llvm-build.log 2>&1
make -j64 >> $src_dir/llvm-build.log 2>&1
cd ..


rm -rf $gcc_build_dir
mkdir $gcc_build_dir
cd $gcc_build_dir
echo "Building with RAJAPerf using GCC..."
cmake -DCMAKE_C_COMPILER=riscv64-unknown-linux-gnu-gcc \
      -DCMAKE_CXX_COMPILER=riscv64-unknown-linux-gnu-g++ \
      -DCMAKE_C_FLAGS="-march=rv64gcv -g -O3 -save-temps -Wdouble-promotion " \
      -DCMAKE_CXX_FLAGS="-march=rv64gcv -g -O3 -save-temps -Wdouble-promotion " \
      -DENABLE_OPENMP=Off \
      .. >> $src_dir/gcc-build.log 2>&1
make -j64 >> $src_dir/gcc-build.log 2>&1
cd ..


###########################
###########################
###########################


cd $llvm_build_dir/src
total_rollback=0
success_rollback=0
error_rollback=0
success_compile=0
error_compile=0


rollback() {

      dir_name=$1
      file_name=$2

      echo "==========" | tee -a $src_dir/rollback.log $src_dir/compile.log
      echo "Processing: $dir_name/$file_name.s..."
      total_rollback=$((total_rollback+1))

      echo "Rolling back $dir_name/$file_name.s..." | tee -a $src_dir/rollback.log
      python /home/s2551341/work/s2551341/rvv-rollback/rvv-rollback.py $dir_name/$file_name.s >> $src_dir/rollback.log 2>&1
      
      if [ $? -ne 0 ]; then
            echo "Rollback failed." | tee -a $src_dir/rollback.log
            error_rollback=$((error_rollback+1))
      else
            echo "Rollback successful." | tee -a $src_dir/rollback.log
            success_rollback=$((success_rollback+1))

            echo "Compiling $dir_name/$file_name.cpp.o..." | tee -a $src_dir/compile.log
            riscv64-unknown-linux-gnu-g++ \
                  -DRUN_RAJA_SEQ \
                  -I$src_dir/build/include \
                  -I$src_dir/src \
                  -I$src_dir/tpl/RAJA/include \
                  -I$src_dir/build/tpl/RAJA/include \
                  -I$src_dir/tpl/RAJA/tpl/camp/include \
                  -I$src_dir/build/tpl/RAJA/tpl/camp/include \
                  -Wall -Wextra \
                  -march=rv64gcv0p7 -O3 -g -Wdouble-promotion -ffast-math -O3 -DNDEBUG -fPIC -std=c++14 \
                  -MD -MT $dir_name/$file_name.cpp.o \
                  -MF $dir_name/$file_name.cpp.o.d \
                  -o $dir_name/$file_name.cpp.o \
                  -c $dir_name/$file_name-rvv0p7.s >> $src_dir/compile.log 2>&1


            if [ $? -eq 0 ]; then
                  echo "Compilation successful." | tee -a $src_dir/compile.log
                  success_compile=$((success_compile+1))
                  cp $dir_name/$file_name.cpp.o ../../$gcc_build_dir/src/$dir_name/CMakeFiles/$dir_name.dir/$file_name.cpp.o
            else
                  echo "Compilation failed." | tee -a $src_dir/compile.log
                  error_compile=$((error_compile+1))
            fi
      fi
}


for dir in $(find . -maxdepth 1 -mindepth 1 -type d ! -name 'CMakeFiles' -exec basename {} \;); do
      for file in $(find $dir -type f -name "*.ii" -exec basename {} .ii \;); do

      rollback $dir $file

      done
done


cd ../../$gcc_build_dir/src


for dir in $(find . -maxdepth 1 -mindepth 1 -type d ! -name 'CMakeFiles' -exec basename {} \;); do
      rm ../lib/lib$dir.a
      files=""

      for file in $(find $dir -type f -name "*.cpp.o" -exec basename {} .cpp.o \;); do
            files="$files $dir/CMakeFiles/$dir.dir/$file.cpp.o"
      done

      echo "==========" | $src_dir/compile.log
      echo "Creating lib$dir.a using: " | tee -a $src_dir/compile.log
      echo $files | tee -a $src_dir/compile.log
      riscv64-unknown-linux-gnu-ar qc ../lib/lib$dir.a $files
      riscv64-unknown-linux-gnu-ranlib ../lib/lib$dir.a
done


rm ../bin/raja-perf.exe
echo "==========" | tee -a $src_dir/compile.log
echo "Linking raja-perf.exe..." | tee -a $src_dir/compile.log
riscv64-unknown-linux-gnu-g++ \
      -Wall -Wextra -march=rv64gc -O3 -g -save-temps \
      -Wdouble-promotion -ffast-math -O3 -DNDEBUG \
      CMakeFiles/raja-perf.exe.dir/RAJAPerfSuiteDriver.cpp.o \
      -o ../bin/raja-perf.exe \
      ../lib/libcommon.a \
      ../lib/libapps.a \
      ../lib/libbasic.a \
      ../lib/libbasic-kokkos.a \
      ../lib/liblcals.a \
      ../lib/liblcals-kokkos.a \
      ../lib/libpolybench.a \
      ../lib/libstream.a \
      ../lib/libstream-kokkos.a \
      ../lib/libalgorithm.a \
      ../lib/libRAJA.a \
      ../lib/libcommon.a \
      ../lib/libRAJA.a \
      ../lib/libcamp.a -ldl 


echo "=========="
echo "Total benchmark files found: $total_rollback"
echo "Number of benchmark files rolled back: $success_rollback"
echo "Number of benchmark files not rolled back: $error_rollback"
echo "Number of benchmark files compiled: $success_compile"
echo "Number of benchmark files not compiled: $error_compile"