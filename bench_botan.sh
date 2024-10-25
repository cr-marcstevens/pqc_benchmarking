#!/bin/bash

REPO="https://github.com/randombit/botan"

CONFOPTIONS="--build-targets=static,cli"

#BENCHALGS="RSA Ed25519 X25519"

BENCHOPTIONS="--msec=10000"

HOSTNAME=`hostname -s`
mkdir $HOSTNAME
cat /proc/cpuinfo | grep "^processor.*: 1$" -B100 | head -n-2 > $HOSTNAME/cpu_info.txt

if [ ! -x "$(command -v stdbuf)" ]; then
	STDBUF=""
else
	STDBUF="stdbuf -oL "
fi

# check for git & openssl
if [ -z $(command -v git) ]; then
	echo "Error: git not found"
	exit 1
fi

if [ ! -d botan ]; then
	echo -n "* Retreiving Botan repository ($REPO)... "
	if git clone "$REPO" >/dev/null 2>/dev/null; then
		echo "[OK]"
	else
		echo "[Failed]"
		exit 3
	fi
else
	cd botan
	echo -n "* Updating Botan repository... "
	git remote update 2>/dev/null >/dev/null
	if [ `git log HEAD..origin/master --oneline | wc -l` -eq 0 ]; then
		echo "[OK]"
	else
		if git pull 2>/dev/null >/dev/null; then
			echo "[OK]"
		else
			echo "[Failed]"
			exit 4
		fi
		# only remove build if there is an update
		rm -rf build 2>/dev/null >/dev/null
	fi
	cd ..
fi

if [ ! -d botan ]; then
	echo "[Failed]"
	echo "Error: Botan directory not found"
	exit 5
fi
cd botan || exit 6

if [ ! -d build ]; then
	echo -n "* Configuring..."
	if ./configure.py --prefix=build $CONFOPTIONS > config.log 2>&1 ; then
		echo "[OK]"
	else
		echo "[Failed]"
		echo "Error: configure failed! Check config.log."
		exit 7
	fi
fi

if [ ! -f Makefile ]; then
	echo "Error: Makefile not found"
fi

echo "* Building..."
make -j 8 install || exit 10

############### BENCHMARK ALGS #####################

LOGFILE=../$HOSTNAME/botan.log
[ -f $LOGFILE ] && rm $LOGFILE

cp config.log $LOGFILE

echo "* Benchmarking..."
$STDBUF ./build/bin/botan speed $BENCHOPTIONS $BENCHALGS | tee -a $LOGFILE 2>&1

