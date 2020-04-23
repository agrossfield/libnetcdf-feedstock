#!/bin/bash

if [[ ! -z "$mpi" && "$mpi" != "nompi" ]]; then
  export PARALLEL="-DENABLE_PARALLEL4=ON -DENABLE_PARALLEL_TESTS=ON"
  export CC=mpicc
  export TESTPROC=4
  export OMPI_MCA_rmaps_base_oversubscribe=yes
  export OMPI_MCA_btl=self,tcp
  export OMPI_MCA_plm=isolated
  export OMPI_MCA_rmaps_base_oversubscribe=yes
  export OMPI_MCA_btl_vader_single_copy_mechanism=none
  mpiexec="mpiexec --allow-run-as-root"
else
  export CC=$(basename ${CC})
  PARALLEL=""
fi

if [[ ${c_compiler} != "toolchain_c" ]]; then
    declare -a CMAKE_PLATFORM_FLAGS
    if [[ ${HOST} =~ .*darwin.* ]]; then
        CMAKE_PLATFORM_FLAGS+=(-DCMAKE_OSX_SYSROOT="${CONDA_BUILD_SYSROOT}")
        # We have a problem with over-stripping of dylibs in the test programs:
        # nm ${PREFIX}/lib/libdf.dylib | grep error_top
        #   000000000006197c S _error_top
        # Then, despite this being linked to explicitly when creating the test programs:
        # ./hdf4_test_tst_chunk_hdf4
        # dyld: Symbol not found: _error_top
        #   Referenced from: ${PREFIX}/lib/libmfhdf.0.dylib
        #   Expected in: flat namespace
        #  in ${PREFIX}/lib/libmfhdf.0.dylib
        # Abort trap: 56
        # Now clearly libmfhdf should autoload libdf but it does not and that is not going to change:
        # https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=556439
        # .. so we must remove our unused stripping instead :-(
        # (it may be possible to arrange this symbol to be in the 'D'ata section instead of 'S'
        #  (symbol in a section other than those above according to man nm), instead though
        #  or to fix ld64 so that it checks for symbols being used in this section).
        export LDFLAGS=$(echo "${LDFLAGS}" | sed "s/-Wl,-dead_strip_dylibs//g")
    else
        CMAKE_PLATFORM_FLAGS+=(-DCMAKE_TOOLCHAIN_FILE="${RECIPE_DIR}/cross-linux.cmake")
    fi
fi

if [[ ${DEBUG_C} == yes ]]; then
  CMAKE_BUILD_TYPE=Debug
else
  CMAKE_BUILD_TYPE=Release
fi

# Build static.
cmake -DCMAKE_INSTALL_PREFIX=${PREFIX} \
      -DCMAKE_INSTALL_LIBDIR="lib" \
      -DCMAKE_PREFIX_PATH=${PREFIX} \
      -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE} \
      -DENABLE_DAP=ON \
      -DENABLE_HDF4=ON \
      -DENABLE_NETCDF_4=ON \
      -DBUILD_SHARED_LIBS=OFF \
      -DENABLE_TESTS=ON \
      -DBUILD_UTILITIES=ON \
      -DENABLE_DOXYGEN=OFF \
      -DCMAKE_C_FLAGS_RELEASE=${CFLAGS} \
      -DCMAKE_C_FLAGS_DEBUG=${CFLAGS} \
      -DENABLE_CDF5=ON \
      ${CMAKE_PLATFORM_FLAGS[@]} \
      ${PARALLEL} \
      ${SRC_DIR}
# ctest  # Run only for the shared lib build to save time.
make install -j${CPU_COUNT} ${VERBOSE_CM}
make clean

# Build shared.
cmake -DCMAKE_INSTALL_PREFIX=${PREFIX} \
      -DCMAKE_INSTALL_LIBDIR="lib" \
      -DCMAKE_PREFIX_PATH=${PREFIX} \
      -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE} \
      -DENABLE_DAP=ON \
      -DENABLE_HDF4=ON \
      -DENABLE_NETCDF_4=ON \
      -DBUILD_SHARED_LIBS=ON \
      -DENABLE_TESTS=ON \
      -DBUILD_UTILITIES=ON \
      -DENABLE_DOXYGEN=OFF \
      -DCMAKE_C_FLAGS_RELEASE=${CFLAGS} \
      -DCMAKE_C_FLAGS_DEBUG=${CFLAGS} \
      -DENABLE_CDF5=ON \
      ${CMAKE_PLATFORM_FLAGS[@]} \
      ${PARALLEL} \
      ${SRC_DIR}
make install -j${CPU_COUNT} ${VERBOSE_CM}
ctest -VV --output-on-failure -j${CPU_COUNT}

if [[ ${c_compiler} != "toolchain_c" ]]; then
    # Fix build paths in cmake artifacts
    for fname in `ls ${PREFIX}/lib/cmake/netCDF/*`; do
        sed -i.bak "s#${BUILD_PREFIX}#\$ENV\{BUILD_PREFIX\}#g" ${fname}
        rm ${fname}.bak
    done

    # Fix build paths in nc-config
    sed -i.bak "s#${BUILD_PREFIX}/bin/${CC}#${CC}#g" ${PREFIX}/bin/nc-config
    rm ${PREFIX}/bin/nc-config.bak
fi
