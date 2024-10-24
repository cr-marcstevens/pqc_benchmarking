#!/bin/bash

OQSREPO="https://github.com/open-quantum-safe/liboqs"

OQSOPTIONS="-DOQS_ENABLE_SIG_STFL_XMSS=ON -DOQS_ENABLE_SIG_STFL_LMS=ON -DOQS_HAZARDOUS_EXPERIMENTAL_ENABLE_SIG_STFL_KEY_SIG_GEN=ON -DOQS_DIST_BUILD=OFF"

STFLBENCHOPTIONS="-d 1000 -i"

BENCHOPTIONS="-d 10 -i"

HOSTNAME=`hostname -s`
mkdir $HOSTNAME
cat /proc/cpuinfo | grep "^processor.*: 1$" -B100 | head -n-2 > $HOSTNAME/cpu_info.txt

if [ ! -x "$(command -v stdbuf)" ]; then
	STDBUF=""
else
	STDBUF="stdbuf -o0 "
fi

# check for git & openssl
if [ -z $(command -v git) ]; then
	echo "Error: git not found"
	exit 1
fi

if [ ! -d liboqs ]; then
	echo -n "* Retreiving libOQS repository ($OQSREPO)... "
	if git clone "$OQSREPO" >/dev/null 2>/dev/null; then
		echo "[OK]"
	else
		echo "[Failed]"
		exit 3
	fi
else
	cd liboqs
	echo -n "* Updating libOQS repository... "
	git remote update 2>/dev/null >/dev/null
	if [ `git log HEAD..origin/main --oneline | wc -l` -eq 0 ]; then
		echo "[OK]"
	else
		git checkout src/oqsconfig.h.cmake
		if git pull 2>/dev/null >/dev/null; then
			echo "[OK]"
		else
			echo "[Failed]"
			exit 4
		fi
		rm -rf build 2>/dev/null >/dev/null
		rm $HOSTNAME/{kem,sig}_*.log

		for d in OQS_ENABLE_SIG_STFL_lms_sha256_h20_w1 OQS_ENABLE_SIG_STFL_lms_sha256_h20_w2 OQS_ENABLE_SIG_STFL_lms_sha256_h20_w4 OQS_ENABLE_SIG_STFL_lms_sha256_h20_w8 ; do
			if [ `grep $d src/oqsconfig.h.cmake | wc -l` -eq 0 ]; then
				echo "#cmakedefine $d 1" >> src/oqsconfig.h.cmake
			fi
		done
	fi
	cd ..
fi

if [ ! -d liboqs ]; then
	echo "[Failed]"
	echo "Error: liboqs directory not found"
	exit 5
fi
cd liboqs || exit 6

if [ ! -d build ]; then
	echo -n "* Preparing build directory..."
	mkdir build 2>/dev/null
	if [ ! -d build ]; then
		echo "[Failed]"
		echo "Error: liboqs/build directory not found"
		exit 7
	fi
	echo "[OK]"
fi
cd build || exit 8

if [ ! -f Makefile ]; then
	echo "* Preparing build files..."
	cmake -G "Unix Makefiles" $OQSOPTIONS ..  || exit 9
	if [ ! -f Makefile ]; then
		echo "Error: Makefile not found"
	fi
fi

echo "* Building..."
make -j 8 || exit 10



# liboqs/build/tests/speed_kem --algs
OQSKEMALGS=`tests/speed_kem --algs | grep -v disabled | tr '\n' ' '`

# liboqs/build/tests/speed_sig --algs
OQSDSSALGS=`tests/speed_sig --algs | grep -v disabled | tr '\n' ' '`

# liboqs/build/tests/speed_sig_stfl --algs
OQSDSSSTFLALGS=`tests/speed_sig_stfl --algs | grep -v disabled | tr '\n' ' '`

echo "KEM      : $OQSKEMALGS"
echo "SIG      : $OQSDSSALGS"
echo "SIG-STFL : $OQSDSSSTFLALGS"

echo "Benchmarking starts in 10 seconds..."
sleep 10

############### BENCHMARK PQC KEMS #####################

LOGBASE=../../$HOSTNAME/kem
if [ -z "$OQSKEMALGS" ]; then
	echo "* Benchmarking..."
	if [ ! -f $LOGBASE.log ]; then
		$STDBUF ./tests/speed_kem $BENCHOPTIONS |& tee $LOGBASE.log
	fi
else
	for a in $OQSKEMALGS; do
		LOGFILE=${LOGBASE}_${a}.log
		if [ -f $LOGFILE ]; then continue; fi
		echo "* Benchmarking $a..."
		./tests/speed_kem $BENCHOPTIONS $a |& tee $LOGFILE
	done
fi

############### BENCHMARK PQC DSAS #####################

LOGBASE=../../$HOSTNAME/sig
if [ -z "$OQSDSSALGS" ]; then
	echo "* Benchmarking..."
	if [ ! -f $LOGBASE.log ]; then
		$STDBUF ./tests/speed_sig $BENCHOPTIONS |& tee $LOGBASE.log
	fi
else
	for a in $OQSDSSALGS; do
		LOGFILE=${LOGBASE}_${a}.log
		if [ -f $LOGFILE ]; then continue; fi
		echo "* Benchmarking $a..."
		./tests/speed_sig $BENCHOPTIONS $a |& tee $LOGFILE
	done
fi

############### BENCHMARK PQC Stateful DSAS #####################

LOGBASE=../../$HOSTNAME/sig_stfl
if [ -z "$OQSDSSSTFLALGS" ]; then
	echo "* Benchmarking..."
	if [ ! -f $LOGBASE.log ]; then
		$STDBUF ./tests/speed_sig_stfl $BENCHOPTIONS |& tee $LOGBASE.log
	fi
else
	for a in $OQSDSSSTFLALGS; do
		LOGFILE=${LOGBASE}_${a}.log
		if [ -f $LOGFILE ]; then continue; fi
		echo "* Benchmarking $a..."
		./tests/speed_sig_stfl $BENCHOPTIONS $a |& tee $LOGFILE
	done
fi
