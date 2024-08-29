#!/bin/bash

git submodule update --init --recursive

src_dir=$(pwd)/RAJAPerf
log_dir=$src_dir/build-logs
gcc_build_dir=build-gcc
llvm_build_dir=build-llvm
rm -rf $log_dir


LLVM_DIR=$(pwd)/riscv-llvm-18-install
RISCV_GNU_DIR=$(pwd)/xuantie-gnu-install
if [ -n "$1" ]; then
      LLVM_DIR=$1
fi
if [ -n "$2" ]; then
      RISCV_GNU_DIR=$2
fi
export PATH=$RISCV_GNU_DIR/bin:$LLVM_DIR/bin:$PATH
export CPATH=$LLVM_DIR/include:$CPATH
export LIBRARY_PATH=$LLVM_DIR/lib:$LLVM_DIR/lib/riscv64-unknown-linux-gnu:$LIBRARY_PATH
export LD_LIBRARY_PATH=$LLVM_DIR/lib:$LLVM_DIR/lib/riscv64-unknown-linux-gnu:$LD_LIBRARY_PATH


###########################
###########################
###########################


cd $src_dir
mkdir $log_dir


rm -rf $llvm_build_dir
mkdir $llvm_build_dir
cd $llvm_build_dir
echo "Building with RAJAPerf using Clang..."
cmake -DCMAKE_C_COMPILER=clang \
      -DCMAKE_CXX_COMPILER=clang++ \
      -DCMAKE_C_FLAGS="-no-integrated-as -g -march=rv64gcv -mllvm --riscv-v-vector-bits-min=128 -O3 -save-temps" \
      -DCMAKE_CXX_FLAGS="-no-integrated-as -g -march=rv64gcv -mllvm --riscv-v-vector-bits-min=128 -O3 -save-temps" \
      -DENABLE_OPENMP=Off \
      .. >> $log_dir/llvm-build.log 2>&1
make -j64 >> $log_dir/llvm-build.log 2>&1
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
      .. >> $log_dir/gcc-build.log 2>&1
make -j64 install >> $log_dir/gcc-build.log 2>&1
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
changed_files=0
changed_and_compiled=0
changed_and_failed=0


rollback() {

      dir_name=$1
      file_name=$2
      changed=0
      rm -rf $log_dir/tmp.log

      echo "==========" | tee -a $log_dir/compile.log
      echo "Processing: $dir_name/$file_name.s..."
      total_rollback=$((total_rollback+1))

      echo "Rolling back $dir_name/$file_name.s..." | tee -a $log_dir/compile.log
      python $src_dir/../rvv-rollback.py $dir_name/$file_name.s >> $log_dir/tmp.log 2>&1
      status=$?
      cat $log_dir/tmp.log >> $log_dir/compile.log

      if grep -q "WARNING" $log_dir/tmp.log; then
            echo "Rollback made changes." | tee -a $log_dir/compile.log
            changed_files=$((changed_files+1))
            changed=1
      fi
      
      if [ $status -ne 0 ]; then
            echo "Rollback failed." | tee -a $log_dir/compile.log
            error_rollback=$((error_rollback+1))
      else
            echo "Rollback successful." | tee -a $log_dir/compile.log
            success_rollback=$((success_rollback+1))

            echo "Compiling $dir_name/$file_name.cpp.o..." | tee -a $log_dir/compile.log
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
                  -c $dir_name/$file_name-rvv0p7.s >> $log_dir/compile.log 2>&1


            if [ $? -eq 0 ]; then
                  if [ $changed -eq 1 ]; then
                        echo "Rollback made changes and succesfully compiled." | tee -a $log_dir/compile.log
                        changed_and_compiled=$((changed_and_compiled+1))
                        echo "$dir_name/$file_name.s" >> $log_dir/changed_and_compiled.log
                  fi
                  echo "Compilation successful." | tee -a $log_dir/compile.log
                  success_compile=$((success_compile+1))
                  cp $dir_name/$file_name.cpp.o ../../$gcc_build_dir/src/$dir_name/CMakeFiles/$dir_name.dir/$file_name.cpp.o
            else
                  if [ $changed -eq 1 ]; then
                        echo "Rollback made changes but compilation failed." | tee -a $log_dir/compile.log
                        changed_and_failed=$((changed_and_failed+1))
                        echo "$dir_name/$file_name.s" >> $log_dir/changed_and_failed.log
                  fi
                  echo "Compilation failed." | tee -a $log_dir/compile.log
                  error_compile=$((error_compile+1))
            fi
      fi
}


if [ -n "$1" ] && [ -n "$2" ]; then
    rollback $1 $2
else
      for dir in $(find . -maxdepth 1 -mindepth 1 -type d ! -name 'CMakeFiles' -exec basename {} \;); do
            for file in $(find $dir -type f -name "*.ii" -exec basename {} .ii \;); do
                  rollback $dir $file
            done
      done
fi


rm -rf $log_dir/tmp.log
cd ../../$gcc_build_dir/src


for dir in $(find . -maxdepth 1 -mindepth 1 -type d ! -name 'CMakeFiles' -exec basename {} \;); do
      rm ../lib/lib$dir.a
      files=""

      for file in $(find $dir -type f -name "*.cpp.o" -exec basename {} .cpp.o \;); do
            files="$files $dir/CMakeFiles/$dir.dir/$file.cpp.o"
      done

      echo "==========" | tee -a $log_dir/compile.log
      echo "Creating lib$dir.a using: " | tee -a $log_dir/compile.log
      echo $files | tee -a $log_dir/compile.log
      riscv64-unknown-linux-gnu-ar qc ../lib/lib$dir.a $files
      riscv64-unknown-linux-gnu-ranlib ../lib/lib$dir.a
done


rm ../bin/raja-perf.exe
echo "==========" | tee -a $log_dir/compile.log
echo "Linking raja-perf.exe..." | tee -a $log_dir/compile.log
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


echo "==========
Total benchmark files found: $total_rollback
>>> Rollback <<<
      successful: $success_rollback
      failed: $error_rollback
      changed: $changed_files
      changed and compiled: $changed_and_compiled
      changed and failed: $changed_and_failed
>>> Compile <<<
      successful: $success_compile
      failed: $error_compile
==========" | tee -a $log_dir/compile.log
echo "GCC build log: $log_dir/gcc-build.log"
echo "LLVM build log: $log_dir/llvm-build.log"
echo "Rollback log: $log_dir/compile.log"
echo "Compile log: $log_dir/compile.log"
echo "Changed and compiled files: $log_dir/changed_and_compiled.log"
echo "Changed and failed files: $log_dir/changed_and_failed.log"
echo "=========="