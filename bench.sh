#!/bin/bash

OQSKEMALGS="BIKE-L5 HQC-256 ML-KEM-1024 FrodoKEM-1344-AES FrodoKEM-1344-SHAKE Classic-McEliece-6688128 Classic-McEliece-6688128f"
OQSDSSALGS="ML-DSA-87 Falcon-1024 Falcon-padded-1024 SPHINCS+-SHA2-256f-simple SPHINCS+-SHA2-256s-simple SPHINCS+-SHAKE-256f-simple SPHINCS+-SHAKE-256s-simple"

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
	echo -n "* Retreiving libOQS repository... "
	if git clone https://github.com/open-quantum-safe/liboqs >/dev/null 2>/dev/null; then
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
	cmake -G "Unix Makefiles" ..  || exit 9
	if [ ! -f Makefile ]; then
		echo "Error: Makefile not found"
	fi
fi

echo "* Building..."
make -j 8 || exit 10

rm ../../kem.log
for a in $OQSKEMALGS; do
	echo -n "* Benchmarking $a..."
	echo "=============================== $a ==============================" >> ../../kem.log
	./tests/speed_kem $a >> ../../kem.log
	echo -e "\n\n" >> ../../kem.log
	echo "[Done]"
done

rm ../../dss.log
for a in $OQSDSSALGS; do
	echo -n "* Benchmarking $a..."
	echo "=============================== $a ==============================" >> ../../dss.log
	./tests/speed_sig $a >> ../../dss.log
	echo -e "\n\n" >> ../../kem.log
	echo "[Done]"
done


rm openssl.log
openssl speed rsa3072 | tee -a openssl.log
openssl speed ed25519 | tee -a openssl.log

BEG=`date +%s`
for (( i=1; i <= 1024; ++i)); do
	openssl genrsa 3072 &>/dev/null
done
END=`date +%s`
echo "RSA3072 keygen: $(($END-$BEG)) seconds for 1024 keygens" | tee -a openssl.log

