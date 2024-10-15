#!/bin/bash

OQSREPO="https://github.com/cr-marcstevens/liboqs" # contains speed_sig_stfl
#OQSREPO="https://github.com/open-quantum-safe/liboqs"

# liboqs/build/tests/speed_kem --algs
OQSKEMALGS=`liboqs/build/tests/speed_kem --algs | grep -v disabled`
#OQSKEMALGS="BIKE-L5 HQC-256 ML-KEM-1024 FrodoKEM-1344-AES FrodoKEM-1344-SHAKE Classic-McEliece-6688128 Classic-McEliece-6688128f"

# liboqs/build/tests/speed_sig --algs
OQSDSSALGS=`liboqs/build/tests/speed_sig --algs | grep -v disabled`
#OQSDSSALGS="ML-DSA-87 Falcon-1024 Falcon-padded-1024 SPHINCS+-SHA2-256f-simple SPHINCS+-SHA2-256s-simple SPHINCS+-SHAKE-256f-simple SPHINCS+-SHAKE-256s-simple"

# liboqs/build/tests/speed_sig_stfl --algs
OQSDSSSTFLALGS=`liboqs/build/tests/speed_sig_stfl --algs | grep -v disabled`
#OQSDSSSTFLALGS="XMSSMT-SHA2_20/2_256 XMSSMT-SHA2_20/4_256 XMSSMT-SHAKE_20/2_256 XMSSMT-SHAKE_20/4_256"

OQSOPTIONS="-DOQS_ENABLE_SIG_STFL_XMSS=ON -DOQS_ENABLE_SIG_STFL_LMS=ON -DOQS_HAZARDOUS_EXPERIMENTAL_ENABLE_SIG_STFL_KEY_SIG_GEN=ON -DOQS_DIST_BUILD=OFF"

BENCHOPTIONS="-d 10 -i"

HOSTNAME=`hostname -s`

# check for git & openssl
if [ -z $(command -v git) ]; then
	echo "Error: git not found"
	exit 1
fi
if [ -z $(command -v openssl) ]; then
	echo "Error: openssl not found"
	exit 2
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

mkdir $HOSTNAME
cat /proc/cpuinfo | grep "^processor.*: 1$" -B100 | head -n-2 > $HOSTNAME/cpu_info.txt

############### BENCHMARK PQC KEMS #####################

LOGFILE=../../$HOSTNAME/kem.log
[ -f $LOGFILE ] && rm $LOGFILE
for a in $OQSKEMALGS; do
	echo -n "* Benchmarking $a..."
	echo "=============================== $a ==============================" >> $LOGFILE
	./tests/speed_kem $BENCHOPTIONS $a >> $LOGFILE
	echo -e "\n\n" >> $LOGFILE
	echo "[Done]"
done

############### BENCHMARK PQC DSAS #####################

LOGFILE=../../$HOSTNAME/dss.log
[ -f $LOGFILE ] && rm $LOGFILE
for a in $OQSDSSALGS; do
	echo -n "* Benchmarking $a..."
	echo "=============================== $a ==============================" >> $LOGFILE
	./tests/speed_sig $BENCHOPTIONS $a >> $LOGFILE
	echo -e "\n\n" >> $LOGFILE
	echo "[Done]"
done

############### BENCHMARK PQC Stateful DSAS #####################

LOGFILE=../../$HOSTNAME/dss_stfl.log
[ -f $LOGFILE ] && rm $LOGFILE
for a in $OQSDSSSTFLALGS; do
	echo -n "* Benchmarking $a..."
	echo "=============================== $a ==============================" >> $LOGFILE
	./tests/speed_sig_stfl $BENCHOPTIONS $a >> $LOGFILE
	echo -e "\n\n" >> $LOGFILE
	echo "[Done]"
done
cd .. # build
cd .. # liboqs

############### BENCHMARK EC & RSA #####################

LOGFILE=$HOSTNAME/openssl.log
[ -f $LOGFILE ] && rm $LOGFILE

openssl speed rsa3072 | tee -a $LOGFILE
openssl speed ed25519 | tee -a $LOGFILE

# rough benchmark for RSA key generation

BEG=`date +%s`
for (( i=1; i <= 1024; ++i)); do
	openssl genrsa 3072 &>/dev/null
done
END=`date +%s`
echo "RSA3072 keygen: $(($END-$BEG)) seconds for 1024 keygens" | tee -a $LOGFILE
