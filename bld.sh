#!/bin/bash
#
# Date: 2018-03-04
#
# This downloads, builds and installs the gcc-7.3.0 compiler and boost
# 1.66. It handles the dependent packages like gmp-6.1.2, mpfr-4.0.1,
# mpc-1.1.0, ppl-1.2, cloog-0.18.4 and binutils-2.30.
#
# To install gcc-7.3.0 in ~/tmp/gcc-7.3.0/rtf/bin you would run this
# script as follows:
#
#    % # Install in ~/tmp/gcc-7.3.0/rtf/bin
#    % bld.sh ~/tmp/gcc-7.3.0 2>&1 | tee bld.log
#
# If you do not specify a directory, then it will install in the
# current directory which means that following command will also
# install in ~/tmp/gcc-7.3.0/rtf/bin:
#
#    % # Install in ~/tmp/gcc-7.3.0/rtf/bin
#    % mkdir -p ~/tmp/gcc-7.3.0
#    % cd ~/tmp/gcc-7.3.0
#    % bld.sh 2>&1 | tee bld.log
#
# This script creates 4 subdirectories:
#
#    Directory  Description
#    =========  ==================================================
#    archives   This is where the package archives are downloaded.
#    src        This is where the package source is located.
#    bld        This is where the packages are built from source.
#    rtf        This is where the packages are installed.
#
# When the build is complete you can safely remove the archives, bld
# and src directory trees to save disk space.
#
# If you want to change the default directory locations, override
# these variables.
#
#    ROOTDIR   The root directory.
#              Default: current directory.
#
#    ARDIR     The archive directory.
#              Default: $ROOTDIR/archives.
#
#    RTFDIR    The release directory.
#              Default: $ROOTDIR/rtf.
#              This is where the bin and lib  directories are
#              located.
#
#    SRCDIR    The source directory.
#              Default: $ROTDIR/src.
#
#    BLDDIR    The build directory.
#              Default: $ROOTDIR/bld.
#
#    TSTDIR    The test directory.
#              Default: $ROOTDIR/test.
#
#    BCXXVER   The boost C++ version.
#              Default: gnu++14 (passed to b2)
#
# Copyright (C) 2013 Joe Linoff
#
# Permission is hereby granted, free of charge, to any person
# obtaining a copy of this software and associated documentation files
# (the "Software"), to deal in the Software without restriction,
# including without limitation the rights to use, copy, modify, merge,
# publish, distribute, sublicense, and/or sell copies of the Software,
# and to permit persons to whom the Software is furnished to do so,
# subject to the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
# BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
# ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# ================================================================
# Trim a string, remove internal spaces, convert to lower case.
# ================================================================
function get-platform-trim {
    echo "$*" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]'
}

# ================================================================
# Get the platform identifier.
#
# The format of the output is:
#   <plat>-<dist>-<ver>-<arch>
#   ^      ^      ^     ^
#   |      |      |     +----- architecture: x86_64, i86pc, etc.
#   |      |      +----------- version: 5.5, 6.4, 10.9, etc.
#   |      +------------------ distribution: debian, centos, macos, ubuntu
#   +------------------------- platform: linux, sunos, darwin
#
# ================================================================
function get-platform
{
    local OS_NAME='unknown'
    local OS_ARCH='unknown'
    local DISTRO_NAME='unknown'
    local DISTRO_VERSION='unknown'

    if uname >/dev/null 2>&1 ; then
        # If uname is present we are in good shape.
        # If it isn't present we have a problem.
        OS_NAME=$(uname 1>/dev/null 2>&1 && get-platform-trim "$(uname)" || echo 'unknown')
        OS_ARCH=$(uname -m 1>/dev/null 2>&1 && get-platform-trim "$(uname -m)" || echo 'unknown')
    fi

    case "$OS_NAME" in
        cygwin)
            # Not well tested.
            OS_NAME='linux'
            DISTRO_NAME=$(awk -F- '{print $1}')
            DISTRO_VERSION=$(awk -F- '{print $2}')
            OS_ARCH=$(awk -F- '{print $3}')
            ;;
        darwin)
            # Not well tested for older versions of Mac OS X.
            DISTRO_NAME=$(get-platform-trim $(system_profiler SPSoftwareDataType | grep 'System Version:' | awk '{print $3}'))
            DISTRO_VERSION=$(get-platform-trim $(system_profiler SPSoftwareDataType | grep 'System Version:' | awk '{print $4}'))
            ;;
        linux)
            if [ -f /etc/centos-release ] ; then
                # centos 6, 7
                DISTRO_NAME='centos'
                DISTRO_VERSION=$(awk '{for(i=1;i<=NF;i++){if($i ~ /^[0-9]/){print $i; break}}}' /etc/centos-release)
            elif [ -f /etc/fedora-release ] ; then
                DISTRO_NAME='fedora'
                DISTRO_VERSION=$(awk '{for(i=1;i<=NF;i++){if($i ~ /^[0-9]/){print $i; break}}}' /etc/fedora-release)
            elif [ -f /etc/redhat-release ] ; then
                # other flavors of redhat.
                DISTRO_NAME=$(get-platform-trim $(awk '{print $1}' /etc/redhat-release))
                DISTRO_VERSION=$(awk '{for(i=1;i<=NF;i++){if($i ~ /^[0-9]/){print $i; break}}}' /etc/redhat-release)
            elif [ -f /etc/os-release ] ; then
                # Tested for recent versions of debian and ubuntu.
                if grep -q '^ID=' /etc/os-release ; then
                    DISTRO_NAME=$(get-platform-trim $(awk -F= '/^ID=/{print $2}' /etc/os-release))
                    DISTRO_VERSION=$(get-platform-trim $(awk -F= '/^VERSION=/{print $2}' /etc/os-release | \
                                                  sed -e 's/"//g' | \
                                                  awk '{print $1}'))
                fi
            fi
            ;;
        sunos)
            # Not well tested.
            OS_NAME='sunos'
            DISTRO_NAME=$(get-platform-trim $(uname -v))
            DISTRO_VERSION=$(get-platform-trim $(uname -r))
            ;;
        *)
            ;;
    esac
    printf '%s-%s-%s-%s\n' "$OS_NAME" "$DISTRO_NAME" "$DISTRO_VERSION" "$OS_ARCH"
}

# ================================================================
# Command header
# Usage  : docmd_hdr $ar $*
# Example: docmd_hdr $ar <args>
# ================================================================
function docmd_hdr {
    local ar=$1
    shift
    local cmd=($*)
    echo
    echo " # ================================================================"
    if [[ "$ar" != "" ]] ; then
        echo " # Archive: $ar"
    fi
    echo " # PWD: "$(pwd)
    echo " # CMD: "${cmd[@]}
    echo " # ================================================================"
}

# ================================================================
# Execute command with decorations and status testing.
# Usage  : docmd $ar <cmd>
# Example: docmd $ar ls -l
# ================================================================
function docmd {
    docmd_hdr $*
    shift
    local cmd=($*)
    ${cmd[@]}
    local st=$?
    echo "STATUS = $st"
    if (( $st != 0 )) ; then
        exit $st;
    fi
}

# ================================================================
# Report an error and exit.
# Usage  : doerr <line1> [<line2> .. <line(n)>]
# Example: doerr "line 1 msg"
# Example: doerr "line 1 msg" "line 2 msg"
# ================================================================
function doerr {
    local prefix="ERROR: "
    for ln in "$@" ; do
        echo "${prefix}${ln}"
        prefix="       "
    done
    exit 1
}

# ================================================================
# Extract archive information.
# Usage  : ard=( $(extract-ar-info $ar) )
# Example: ard=( $(extract-ar-info $ar) )
#          fn=${ard[1]}
#          ext=${ard[2]}
#          d=${ard[3]}
# ================================================================
function extract-ar-info {
    local ar=$1
    local fn=$(basename $ar)
    local ext=$(echo $fn | awk -F. '{print $NF}')
    local d=${fn%.*tar.$ext}
    echo $ar
    echo $fn
    echo $ext
    echo $d
}

# ================================================================
# Print a banner for a new section.
# Usage  : banner STEP $ar
# Example: banner "DOWNLOAD" $ar
# Example: banner "BUILD" $ar
# ================================================================
function banner {
    local step=$1
    local ard=( $(extract-ar-info $2) )
    local ar=${ard[0]}
    local fn=${ard[1]}
    local ext=${ard[2]}
    local d=${ard[3]}
    echo
    echo '# ================================================================'
    echo "# Step   : $step"
    echo "# Archive: $ar"
    echo "# File   : $fn"
    echo "# Ext    : $ext"
    echo "# Dir    : $d"
    echo '# ================================================================'
}

# ================================================================
# Make a set of directories
# Usage  : mkdirs <dir1> [<dir2> .. <dir(n)>]
# Example: mkdirs foo bar spam spam/foo/bar
# ================================================================
function mkdirs {
    local ds=($*)
    #echo "mkdirs"
    for d in ${ds[@]} ; do
        #echo "  testing $d"
        if [ ! -d $d ] ; then
            #echo "    creating $d"
            mkdir -p $d
            (( $? )) && doerr "directory creation failed: $d"
        fi
    done
}

# ================================================================
# Check the current platform to see if it is in the tested list,
# if it isn't, then issue a warning.
# ================================================================
function check-platform
{
    local plat=$(get-platform)
    local tested_plats=(
        'linux-centos-6.9-x86_64'
        'darwin-macos-10.13.3-x86_64'
    )
    local plat_found=0

    echo "PLATFORM: $plat"
    for tested_plat in ${tested_plats[@]} ; do
        if [[ "$plat" == "$tested_plat" ]] ; then
            plat_found=1
            break
        fi
    done
    if (( $plat_found == 0 )) ; then
        echo "WARNING: This platform ($plat) has not been tested."
    fi
}

# ================================================================
# DATA
# ================================================================
# List of archives
# The order is important.
ARS=(
    http://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.15.tar.gz
    https://ftp.gnu.org/gnu/m4/m4-1.4.18.tar.gz
    https://ftp.gnu.org/gnu/autoconf/autoconf-2.69.tar.gz
    https://gmplib.org/download/gmp/gmp-6.1.2.tar.bz2
    http://www.mpfr.org/mpfr-current/mpfr-4.0.1.tar.gz
    https://ftp.gnu.org/gnu/mpc/mpc-1.1.0.tar.gz
    http://bugseng.com/external/ppl/download/ftp/releases/1.2/ppl-1.2.tar.bz2
    http://www.bastoul.net/cloog/pages/download/cloog-0.18.4.tar.gz
    https://ftp.gnu.org/gnu/gcc/gcc-7.3.0/gcc-7.3.0.tar.gz
    https://ftp.gnu.org/gnu/binutils/binutils-2.30.tar.bz2
    https://dl.bintray.com/boostorg/release/1.66.0/source/boost_1_66_0.tar.bz2
    #
    # Why glibc is disabled (for now).
    #
    # glibc does not work on CentOS because the versions of the shared
    # libraries we are building are not compatable with installed
    # shared libraries.
    #
    # This is the run-time error: ELF file OS ABI invalid that I see
    # when I try to run binaries compiled with the local glibc-2.15.
    #
    # Note that the oldest supported ABI for glibc-2.15 is 2.2. The
    # CentOS 5.5 ABI is 0.
    # http://ftp.gnu.org/gnu/glibc/glibc-2.15.tar.bz2
)

# ================================================================
# MAIN
# ================================================================
umask 0

check-platform

# Suggested by jeaye 2014-09-17
unset LIBRARY_PATH CPATH C_INCLUDE_PATH PKG_CONFIG_PATH CPLUS_INCLUDE_PATH INCLUDE

# Read the command line argument, if it exists.
if (( $# == 1 )) ; then
    # This logic allows readlink to be avoided because it
    # has different options on linux and mac. In particular,
    # on the mac, it cannot handle undefined directories.
    if [ ! -d "$1" ] ; then
        mkdir -p "$1"
        (( $? )) && doerr "directory creation failed: $1" || true
    fi
    cd "$1"
    _ROOTDIR=$(pwd)
elif (( $# > 1 )) ; then
    doerr "too many command line arguments ($#), only zero or one is allowed" "foo"
else
    _ROOTDIR=$(pwd)
fi

# Setup the directories.
# Allow the user to override.
# For example:
#    $ MR=/opt/gcc/7.3.0
#    $ ROOTDIR=$MR RTFDIR=$MR ARDIR=$MR/cache SRCDIR=$MR/pkg/src BLDDIR=$MR/pkg/bld ./bld.sh
: ${ROOTDIR=$_ROOTDIR}
: ${ARDIR=$ROOTDIR/archives}
: ${RTFDIR=$ROOTDIR/rtf}
: ${SRCDIR=$ROOTDIR/src}
: ${BLDDIR=$ROOTDIR/bld}
: ${TSTDIR=$ROOTDIR/test}
: ${BCXXVER=gnu++14}

export PATH="${RTFDIR}/bin:${PATH}"
export LD_LIBRARY_PATH="${RTFDIR}/lib:${RTFDIR}/lib64:${LD_LIBRARY_PATH}"

echo
echo "# ================================================================"
echo '# Version    : gcc-7.3.0 2018-03-04'
echo "# RootDir    : $ROOTDIR"
echo "# ArchiveDir : $ARDIR"
echo "# RtfDir     : $RTFDIR"
echo "# SrcDir     : $SRCDIR"
echo "# BldDir     : $BLDDIR"
echo "# TstDir     : $TSTDIR"
echo "# Gcc        : "$(which gcc 2>/dev/null | head -1)
echo "# GccVersion : "$(gcc --version 2>/dev/null | head -1)
echo "# BoostCxxVer: $BCXXVER"
echo "# Hostname   : "$(hostname)
echo "# O/S        : "$(uname -s -r -v -m)
echo "# Date       : "$(date)
echo "# Platform   : "$(get-platform)
echo "# ================================================================"

mkdirs $ARDIR $RTFDIR $SRCDIR $BLDDIR

# ================================================================
# Download
# ================================================================
for ar in ${ARS[@]} ; do
    banner 'DOWNLOAD' $ar
    ard=( $(extract-ar-info $ar) )
    fn=${ard[1]}
    ext=${ard[2]}
    d=${ard[3]}
    if [  -f "${ARDIR}/$fn" ] ; then
        echo "INFO:${LINENO}: already downloaded $fn"
    else
        # get
        docmd $ar curl -L -o $ARDIR/$fn $ar
        [ -z "$ar" ] && doerr "archive download failed: $ar." || true
    fi
done

# ================================================================
# Extract
# ================================================================
for ar in ${ARS[@]} ; do
    banner 'EXTRACT' $ar
    ard=( $(extract-ar-info $ar) )
    fn=${ard[1]}
    ext=${ard[2]}
    d=${ard[3]}
    sd="$SRCDIR/$d"
    if [ -d $sd ] ; then
        echo "INFO:${LINENO}: already extracted $fn"
    else
        # unpack
        pushd $SRCDIR
        docmd $ar tar xf  ${ARDIR}/$fn
        popd
        if [ ! -d $sd ] ;  then
            # Some archives (like gcc-g++) overlay. We create a dummy
            # directory to avoid extracting them every time.
            docmd $ar mkdir -p $sd
        fi
    fi
done

# ================================================================
# Build
# ================================================================
for ar in ${ARS[@]} ; do
    banner 'BUILD' $ar
    ard=( $(extract-ar-info $ar) )
    fn=${ard[1]}
    ext=${ard[2]}
    d=${ard[3]}
    sd="$SRCDIR/$d"
    bd="$BLDDIR/$d"
    if [ -d $bd ] ; then
        echo "INFO:${LINENO}: already built $sd"
    else
        # Build
        regex='^gcc-g\+\+.*'
        if [[ $fn =~ $regex ]] ; then
            # Don't build/configure the gcc-g++ package explicitly because
            # it is part of the regular gcc package.
            echo "INFO:${LINENO}: skipping $sd"
            # Dummy
            continue
        fi

        # Set the CONF_ARGS
        plat=$(get-platform)
        run_conf=1
        run_boost_bootstrap=0
        case "$d" in
            autoconf-*)
                CONF_ARGS=(
                    --prefix=${RTFDIR}
                )
                ;;

            binutils-*)
                # Binutils will not compile with strict error
                # checking on so I disabled -Werror by setting
                # --disable-werror.
                CONF_ARGS=(
                    --disable-cloog-version-check
                    --disable-ppl-version-check
                    --disable-werror
                    --enable-cloog-backend=isl
                    --enable-lto
                    --enable-libssp
                    --enable-gold
                    --prefix=${RTFDIR}
                    --with-cloog=${RTFDIR}
                    --with-gmp=${RTFDIR}
                    --with-mlgmp=${RTFDIR}
                    --with-mpc=${RTFDIR}
                    --with-mpfr=${RTFDIR}
                    --with-ppl=${RTFDIR}
                    CC=${RTFDIR}/bin/gcc
                    CXX=${RTFDIR}/bin/g++
                )
                ;;

            boost_*)
                # The boost configuration scheme requires
                # that the build occur in the source directory.
                run_conf=0
                run_boost_bootstrap=1
                ;;

            cloog-*)
                GMPDIR=$(ls -1d ${BLDDIR}/gmp-*)
                CONF_ARGS=(
                    --prefix=${RTFDIR}
                    --with-gmp-builddir=${GMPDIR}
                    --with-gmp=build
                )
                ;;

            gcc-*)
                # We are using a newer version of CLooG (0.18.0).
                # I have also made stack protection available
                # (similar to DEP in windows).
                CONF_ARGS=(
                    --disable-cloog-version-check
                    --disable-ppl-version-check
                    --disable-multilib
                    --enable-cloog-backend=isl
                    --enable-gold
                    --enable-languages='c,c++'
                    --enable-lto
                    --enable-libssp
                    --prefix=${RTFDIR}
                    --with-cloog=${RTFDIR}
                    --with-gmp=${RTFDIR}
                    --with-isl=${RTFDIR}
                    --with-mlgmp=${RTFDIR}
                    --with-mpc=${RTFDIR}
                    --with-mpfr=${RTFDIR}
                    --with-ppl=${RTFDIR}
                )
                # Fixup for darwin.
                if [[ "$plat" =~ ^darwin- ]] ; then
                    # Special case for darwin, the gcc package expects to
                    # see:
                    #    iconv()
                    #    iconv_open()
                    #    iconv_close()
                    # But they are built as:
                    #    _libiconv()
                    #    _libiconv_open()
                    #    _libiconv_close()
                    echo "INFO:${LINENO}: fixing libiconv references for $plat"
                    set -x
                    LC_ALL=C time sed -i.bak -e 's@\(iconv[^\(]*(\)@_lib\1@g' $(grep -l -r 'iconv[^\(]*(' $sd 2>/dev/null)
                    { set +x; } 2>/dev/null
                fi
                ;;

            glibc-*)
                CONF_ARGS=(
                    --enable-static-nss=no
                    --prefix=${RTFDIR}
                    --with-binutils=${RTFDIR}
                    --with-elf
                    CC=${RTFDIR}/bin/gcc
                    CXX=${RTFDIR}/bin/g++
                )
                ;;

            gmp-*)
                CONF_ARGS=(
                    --enable-cxx
                    --prefix=${RTFDIR}
                )
                if [[ "$plat" == "linux-cygwin_nt-6.1-wow64" ]] ; then
                    CONF_ARGS+=('--enable-static')
                    CONF_ARGS+=('--disable-shared')
                fi
                ;;

            libiconv-*)
                CONF_ARGS=(
                    --prefix=${RTFDIR}
                )
                ;;

            m4-*)
                CONF_ARGS=(
                    --prefix=${RTFDIR}
                )
                ;;

            mpc-*)
                CONF_ARGS=(
                    --prefix=${RTFDIR}
                    --with-gmp=${RTFDIR}
                    --with-mpfr=${RTFDIR}
                )
                if [[ "$plat" == "linux-cygwin_nt-6.1-wow64" ]] ; then
                    CONF_ARGS+=('--enable-static')
                    CONF_ARGS+=('--disable-shared')
                fi
                ;;

            mpfr-*)
                CONF_ARGS=(
                    --prefix=${RTFDIR}
                    --with-gmp=${RTFDIR}
                )
                ;;

            ppl-*)
                CONF_ARGS=(
                    --prefix=${RTFDIR}
                    --with-gmp=${RTFDIR}
                )
                if [[ "$plat" == "linux-cygwin_nt-6.1-wow64" ]] ; then
                    # Cygwin does not implement long double so I cheated.
                    CONF_ARGS+=('--enable-static')
                    CONF_ARGS+=('--disable-shared')
                fi

                # We need a special fix for the pax archive prompt.
                # Change the configure code.
                if [ ! -f "$sd/configure.orig" ] ; then
                    # Fix the configure code so that it does not use 'pax -r'.
                    # The problem with 'pax -r' is that it expects a "." input
                    # from stdin which breaks the flow.
                    cp $sd/configure{,.orig}
                    sed -e "s/am__untar='pax -r'/am__untar='tar -xf'  #am__untar='pax -r'/" \
                        $sd/configure.orig >$sd/configure
                fi

                # We need to make a special fix here
                src="$sd/src/mp_std_bits.defs.hh"
                if [ -f $src ] ; then
                    if [ ! -f $src.orig ] ; then
                        if ! grep -q '__GNU_MP_VERSION' $src ; then
                            cp $src $src.orig
                            cat $src.orig | \
                                awk \
'{ \
  if($1=="namespace" && $2 == "std") { \
    printf("// Automatically patched by bld.sh for gcc-7.3.0.\n"); \
    printf("#define tininess_before tinyness_before\n"); \
    printf("#if __GNU_MP_VERSION < 5  || (__GNU_MP_VERSION == 5 && __GNU_MP_VERSION_MINOR < 1)\n");
  } \
  print $0; \
  if($1 == "}" && $2=="//" && $3=="namespace") { \
    printf("#endif  // #if __GNU_MP_VERSION < 5  || (__GNU_MP_VERSION == 5 && __GNU_MP_VERSION_MINOR < 1)\n");
  } \
}' >$src
                        fi
                    fi
                fi
                ;;

            *)
                doerr "unrecognized package: $d"
                ;;
        esac

        mkdir -p $bd
        pushd $bd
        if (( $run_conf )) ; then
            docmd $ar $sd/configure --help
            docmd $ar $sd/configure ${CONF_ARGS[@]}
            docmd $ar make
            docmd $ar make install
        fi
        if (( $run_boost_bootstrap )) ; then
            # CITATION: http://www.boost.org/build/doc/html/bbv2/overview/invocation.html
            pushd $sd
            docmd $ar which g++
            docmd $ar g++ --version
            docmd $ar $sd/bootstrap.sh --prefix=${RTFDIR} toolset=gcc
            docmd $ar ./b2 -j4 toolset=gcc variant=release link=shared,static threading=multi cxxflags="-std=$BCXXVER" install
            popd
        fi

        # Redo the tests if anything changed.
        if [ -d $TSTDIR ] ; then
            rm -rf $TSTDIR
        fi
        popd
    fi
done

# ================================================================
# Create environment setup tools.
# ================================================================
if [ ! -f $RTFDIR/bin/gcc-enable ] ; then
    echo "INFO:${LINENO}: Creating gcc-enable and gcc-disable"
    cat >$RTFDIR/bin/gcc-enable <<EOF
export PATH="$RTFDIR/bin:\$PATH"
export LD_LIBRARY_PATH="$RTFDIR/lib64:$RTFDIR/lib:\$LD_LIBRARY_PATH"
EOF
    cat >$RTFDIR/bin/gcc-disable <<EOF
export PATH="\$(echo \$PATH | sed -e 's@$RTFDIR/bin:@@')"
export LD_LIBRARY_PATH="\$(echo \$LD_LIBRARY_PATH | sed -e 's@$RTFDIR/lib64:$RTFDIR/lib:@@')"
EOF
    chmod a+x $RTFDIR/bin/gcc-enable
    chmod a+x $RTFDIR/bin/gcc-disable
fi

# ================================================================
# Test
# ================================================================
if [ -d $TSTDIR ] ; then
    echo "INFO:${LINENO}: skipping tests"
else
    docmd "MKDIR" mkdir -p $TSTDIR
    pushd $TSTDIR
    docmd "LOCAL TEST  1" which g++
    docmd "LOCAL TEST  2" which gcc
    docmd "LOCAL TEST  3" which c++
    docmd "LOCAL TEST  4" g++ --version

    # Simple aliveness test.
    cat >test1.cc <<EOF
#include <iostream>
using namespace std;
int main()
{
  cout << "IO works" << endl;
  return 0;
}
EOF
    docmd "LOCAL TEST  5" g++ -O3 -Wall -o test1.bin test1.cc
    docmd "LOCAL TEST  6" ./test1.bin

    docmd "LOCAL TEST  7" g++ -g -Wall -o test1.dbg test1.cc
    docmd "LOCAL TEST  8" ./test1.dbg

    # Simple aliveness test for boost.
    cat >test2.cc <<EOF
#include <iostream>
#include <boost/algorithm/string.hpp>
using namespace std;
using namespace boost;
int main()
{
  string s1(" hello world! ");
  cout << "value      : '" << s1 << "'" <<endl;

  to_upper(s1);
  cout << "to_upper() : '" << s1 << "'" <<endl;

  trim(s1);
  cout << "trim()     : '" << s1 << "'" <<endl;

  return 0;
}
EOF
    docmd "LOCAL TEST  9" g++ -O3 -Wall -o test2.bin test2.cc
    docmd "LOCAL TEST 10" ./test2.bin

    docmd "LOCAL TEST 11" g++ -g -Wall -o test2.dbg test2.cc
    docmd "LOCAL TEST 12" ./test2.dbg

    docmd "LOCAL TEST" ls -l

    # Simple aliveness test for C++11.
    # Initializer lists, auto and foreach.
    cat >test3.cc <<EOF
#include <iostream>
#include <string>
#include <vector>

using namespace std;

int main()
{
  vector<int> v1 = {10, 21, 32, 43};
  vector<string> v2 = {"foo", "bar", "spam"};

  for (auto i : v1) {
    cout << "v1: " << i << endl;
  }

  for (auto i : v2) {
    cout << "v2: " << i << endl;
  }
  return 0;
}
EOF
    docmd "LOCAL TEST 13" g++ -std=c++11 -O3 -Wall -o test3.bin test3.cc
    docmd "LOCAL TEST 14" ./test3.bin

    docmd "LOCAL TEST 15" g++ -std=c++11 -g -Wall -o test3.dbg test3.cc
    docmd "LOCAL TEST 16" ./test3.dbg

    # A slightly more complex test for C++-11.
    cat >test4.cc <<EOF
// Example implementation of a quicksort that uses a number
// of C++-11 constructs.
#include <algorithm>
#include <chrono>
#include <utility>
#include <vector>
#include <iostream>
#include <random>
using namespace std;

template <typename T>
auto insertionSort(vector<T>& a, size_t beg, size_t end) -> void
{
  for(auto i=beg+1; i<=end; ++i) {
    // all items from beg to i-1 are sorted
    // insert the new one in the appropriate slot
    auto j = i;
    while (j>0 && a[j-1] > a[j]) {
      swap(a[j], a[j-1]);
      --j;
    }
  }
}

template<typename T>
auto partition(vector<T>& a, size_t beg, size_t end) -> size_t
{
  // Randomly select the pivot using a uniform distribution.
  random_device rd;
  mt19937 mt(rd());
  uniform_int_distribution<size_t> dis(beg, end);
  auto idx = dis(mt);
  T pivot = a[idx];
  swap(a[end], a[idx]); // reserve the end slot

  auto i = beg;
  for(auto j=beg; j<end; ++j) {  // up to end - 1
    if (a[j] <= pivot) {
      swap(a[i], a[j]);
      ++i;
    }
  }
  swap(a[i], a[end]);
  return i;
}

template <typename T, size_t M=32>
auto quickSort(vector<T>& a, size_t beg, size_t end) -> void
{
  if ((end - beg) < M) {
    insertionSort(a, beg, end);
  }
  else {
    auto pivot = partition(a, beg, end);
    if (pivot > 0) {
      quickSort(a, 0, pivot-1);   // left
    }
    if (pivot < end) {
      quickSort(a, pivot+1, end); // right
    }
  }
}

auto test() -> bool
{
  int M = 100000; // range of numbers in the array
  int N = 100;    // array size

  cout << "test" << endl;
  random_device rd;
  mt19937 mt(rd());
  uniform_int_distribution<size_t> dis(1, M);

  vector<int> a;
  cout << "populating array with N=" << N << " where 1 <= a[i] <= " << M << endl;
  auto now = chrono::system_clock::now();
  do {
    if (a.size()) {
      cout << "trying again - previous attempt was already sorted" << endl;
    }
    a.clear();
    for(auto i=1; i<N; ++i) {
      int ran = dis(mt);
      a.push_back(ran);
    }
  } while (is_sorted(a.begin(), a.end()));
  auto end = chrono::system_clock::now();
  auto ms = chrono::duration_cast<chrono::milliseconds>(end-now).count();
  cout << "elapsed time: " << ms << "ms" << endl;

  cout << "sorting..." << endl;
  now = chrono::system_clock::now();
  quickSort(a, 0, a.size()-1);
  end = chrono::system_clock::now();
  ms = chrono::duration_cast<chrono::milliseconds>(end-now).count();
  cout << "elapsed time: " << ms << "ms" << endl;

  cout << "testing..." << endl;
  if (is_sorted(a.begin(), a.end())) {
    cout << "PASSED" << endl;
    return true;
  }
  cout << "FAILED" << endl;
  return false;
}

int main()
{
  return test() ? 0 : 1;
}
EOF
    docmd "LOCAL TEST 17" g++ -std=c++11 -O3 -Wall -o test4.bin test4.cc
    docmd "LOCAL TEST 18" ./test4.bin

    docmd "LOCAL TEST 19" g++ -std=c++11 -g -Wall -o test4.dbg test4.cc
    docmd "LOCAL TEST 20" ./test4.dbg

    docmd "LOCAL TEST" ls -l

    popd
fi

# ================================================================
# Done.
# ================================================================
cat <<EOF

gcc-7.3.0 build completed successfully.

To enable it in your environment:

    \$ source $RTFDIR/bin/gcc-enable
    \$ gcc --version
    \$ g++ --version

To disable it:

    \$ source $RTFDIR/bin/gcc-disable

Done.
EOF
