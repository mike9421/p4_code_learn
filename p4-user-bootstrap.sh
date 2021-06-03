#!/bin/bash

# ubuntu 20.04

alias python=python3
alias pip=pip3

p4=/home/`whoami`/P4
mkdir -p /home/`whoami`/P4 && cd $p4

sudo apt-get update -y && sudo apt-get install python3 python3-pip-y

# Print script commands and exit on errors.
set -xe

#Src 
BMV2_COMMIT="dc1d9cec1a19f893fe312ed9d72dc63cfcad4b9b"         # Mar 17, 2021 stable
PI_COMMIT="35ac4fc80d5a3560d171dc8aa60d104bfa31d37a"           # Mar 16, 2021 stable
P4C_COMMIT="eab654a4e06c823e1876ef52e4a0dd70cf5763cc"          # Jan 30, 2021 bf-stable
PROTOBUF_COMMIT="19fb89416f3fdc2d6668f3738f444885575285bc"     # Jan 14, 2021 v1.36.4
GRPC_COMMIT="v1.36.4"                                          # Mar 19, 2021 v1.36.4
THRIFT_COMMIT="0d8da22dba430c379de04ff48e507e7277f4ea21"       # Apr 11, 2018 origin/0.11.0
NANOMSG_COMMIT="096998834451219ee7813d8977f6a4027b0ccb43"      # Jan 10, 2016 1.0.0
NNPY_COMMIT="d8f260a176212bfe5f6626942c487b7d90842414"         # Feb  9, 2018 master-----Bump version to 1.4.2
OVS_COMMIT="fdd82b2318dd266e39e831995deb17aa50900d85"          # Apr 14, 2021 branch-2.14
MININET_COMMIT="57294d013e780cccc6b4b9af151906b382c4d8a7"      # Mar 29, 2021 master
DPDK_COMMIT="v20.11" # "b1d36cf828771e28eb0130b59dcf606c2a0bc94d"         # Nov 28, 2020 branch-v20.11

#Get the number of cores to speed up the compilation process
NUM_CORES=`grep -c ^processor /proc/cpuinfo`

git clone https://github.com/faucetsdn/ryu.git

# ------------------------------------------- OVS ------------------------------------------- #
sudo apt-get install libssl1.1 libcap-ng-dev libcap-ng0 libcap-ng-utils autoconf automake libtool wget flake8 netcat curl tftp netstat-nat -y
git clone https://github.com/openvswitch/ovs.git
cd ovs
git checkout ${OVS_COMMIT}
./boot.sh
./configure --with-linux=/lib/modules/$(uname -r)/build
make -j${NUM_CORES}
sudo make install |  tee  $p4/log/ovs.log
sudo make modules_install |  tee -a $p4/log/ovs.log
sudo /sbin/modprobe openvswitch  |  tee  -a $p4/log/ovs.log
sudo /sbin/lsmod | grep openvswitch |  tee -a $p4/log/ovs.log
echo 'export PATH=$PATH:/usr/local/share/openvswitch/scripts' | sudo  tee -a /home/.bashrc
source /home/.bashrc
cd $p4

# ------------------------------------------- DPDK ------------------------------------------- #
sudo apt-get update && sudo apt-get install meson ninja-build python3-pyelftools build-essential libnuma-dev libarchive13 libarchive-dev libelf-dev -y
git clone https://github.com/DPDK/dpdk.git
cd dpdk
git checkout ${DPDK_COMMIT}
export DPDK_DIR=`pwd`
export DPDK_BUILD=$DPDK_DIR/build
meson -Dexamples=all build
ninja -C build
sudo ninja -C build install
sudo ldconfig
pkg-config --modversion libdpdk

sudo modprobe uio_pci_generic vfio-pci

sudo mkdir -p /dev/hugepages
sudo mountpoint -q /dev/hugepages || sudo mount -t hugetlbfs nodev /dev/hugepages
echo 1024 | sudo tee /sys/devices/system/node/node0/hugepages/hugepages-2048kB/nr_hugepages
sudo build/app/dpdk-testpmd -c7 --vdev=net_pcap0,iface=eth0 --vdev=net_pcap1,iface=eth1 -- -i --nb-cores=2 --nb-ports=2 --total-num-mbufs=2048


# ------------------------------------------- Mininet ------------------------------------------- #
git clone git://github.com/mininet/mininet
cd mininet
git checkout ${MININET_COMMIT}
cd $p4
sudo PYTHON=python3 mininet/util/install.sh -n3w |  tee  $p4/log/mininet.log  # install Python 3 Mininet
# sudo mn --switch ovsbr --test pingall #########################################################

# ------------------------------------------- Protobuf ------------------------------------------- #
sudo apt-get install autoconf automake libtool curl make g++ unzip -y
git clone https://github.com/protocolbuffers/protobuf.git
cd protobuf
git checkout ${PROTOBUF_COMMIT}
git submodule update --init --recursive
export CFLAGS="-Os"
export CXXFLAGS="-Os"
export LDFLAGS="-Wl,-s"
./autogen.sh
./configure --prefix=/usr
make -j${NUM_CORES}
sudo make check |  tee -a $p4/log/protobuf.log
sudo make install |  tee -a $p4/log/protobuf.log
sudo ldconfig
unset CFLAGS CXXFLAGS LDFLAGS
# Force install python module
cd python
sudo python3 setup.py install
cd $p4

# ------------------------------------------- gRPC ------------------------------------------- #
sudo apt-get install build-essential autoconf libtool pkg-config cmake clang libc++-dev libssl-dev -y
git clone https://github.com/grpc/grpc.git
cd grpc
git checkout ${GRPC_COMMIT}
git submodule update --init --recursive
export LDFLAGS="-Wl,-s"
# Install gRPC and its dependencies
mkdir -p "cmake/build"
pushd "cmake/build"
cmake -DBUILD_SHARED_LIBS=ON \
  -DCMAKE_BUILD_TYPE=Release \
  -DgRPC_INSTALL=ON \
  -DgRPC_BUILD_TESTS=OFF \
  -DgRPC_SSL_PROVIDER=package \
  ../..
make -j${NUM_CORES}
sudo make check |  tee  $p4/log/grpc.log
sudo make install |  tee -a $p4/log/grpc.log
sudo ldconfig
unset LDFLAGS
popd
# Build helloworld example using cmake
mkdir -p "examples/cpp/helloworld/cmake/build"
pushd "examples/cpp/helloworld/cmake/build"
cmake ../..
make -j${NUM_CORES}
popd
cd $p4
# Install gRPC Python Package
sudo pip3 install grpcio

# ------------------------------------------- BMv2 deps (needed by PI) ------------------------------------------- #
sudo apt-get install automake bison flex g++ git libboost-all-dev libevent-dev libssl-dev libtool make pkg-config -y
# git clone -b 0.11.0 https://github.com/apache/thrift.git thrift
# cd thrift
git clone https://github.com/apache/thrift.git
cd thrift
git checkout ${THRIFT_COMMIT}
./bootstrap.sh
./configure --with-cpp=yes --with-c_glib=no --with-java=no --with-ruby=no --with-erlang=no --with-go=no --with-nodejs=no
make -j${NUM_CORES}
# make -k check ###################################################################################
# make cross 
sudo make install |  tee $p4/log/thrift.log
cd lib/py
sudo python3 setup.py install
cd $p4

# wget https://github.com/nanomsg/nanomsg/archive/1.0.0.tar.gz -O nanomsg.tar.gz
# tar -xzvf nanomsg.tar.gz
# cd nanomsg
git clone https://github.com/nanomsg/nanomsg.git
cd nanomsg
git checkout ${NANOMSG_COMMIT}
mkdir build
cd build
cmake .. -DCMAKE_INSTALL_PREFIX=/usr
cmake --build .
# ctest .  #####################################################################################
sudo cmake --build . --target install |  tee  $p4/log/nanomsg.log
sudo ldconfig
cd $p4

git clone https://github.com/nanomsg/nnpy.git
cd nnpy
git checkout ${NNPY_COMMIT}
sudo pip3 install cffi
sudo pip3 install . |  tee  $p4/log/nnpy.log
sudo pip3 install nnpy
cd $p4

# ------------------------------------------- PI/P4Runtime ------------------------------------------- #
sudo apt-get install libreadline-dev valgrind libjudy-dev libtool-bin libboost-dev libboost-system-dev libboost-thread-dev -y
git clone https://github.com/p4lang/PI.git
cd PI
git checkout ${PI_COMMIT}
git submodule update --init --recursive
./autogen.sh
./configure --with-proto
make -j${NUM_CORES}
sudo make check |  tee  $p4/log/PI.log
sudo make install |  tee -a $p4/log/PI.log
sudo ldconfig
cd $p4

# ------------------------------------------- Bmv2 ------------------------------------------- #
sudo apt-get install automake cmake libjudy-dev libgmp-dev libpcap-dev libboost-dev libboost-test-dev libboost-program-options-dev libboost-system-dev libboost-filesystem-dev libboost-thread-dev libevent-dev libtool flex bison pkg-config g++ libssl-dev -y
git clone https://github.com/p4lang/behavioral-model.git
cd behavioral-model
git checkout ${BMV2_COMMIT}
git submodule update --init --recursive
./autogen.sh
./configure --enable-debugger --with-pi --with-pdfixed
make -j${NUM_CORES}
sudo make check |  tee  $p4/log/bmv2.log
sudo make install |  tee -a $p4/log/bmv2.log
sudo ldconfig
# Simple_switch_grpc target
cd targets/simple_switch_grpc
./autogen.sh
./configure --with-thrift
make -j${NUM_CORES}
# sudo make check |  tee  $p4/log/simple_switch_grpc.log  ###############################################
sudo make install |  tee -a $p4/log/simple_switch_grpc.log 
sudo ldconfig
cd $p4

# ------------------------------------------- P4C ------------------------------------------- #
sudo apt-get install cmake g++ git automake libtool libgc-dev bison flex doxygen graphviz texlive-full -y
sudo pip3 install scapy ply ipaddr
git clone https://github.com/p4lang/p4c
cd p4c
git checkout ${P4C_COMMIT}
git submodule update --init --recursive
sudo python3 backends/ebpf/build_libbpf
sudo apt-get install clang llvm libpcap-dev libelf-dev iproute2 net-tools
pip3 install --user pyroute2 # ply==3.8 scapy==2.4.0
mkdir -p build
cd build
cmake ..
make -j${NUM_CORES}
sudo make check |  tee  $p4/log/p4c.log
sudo make install |  tee -a $p4/log/p4c.log
sudo ldconfig
cd $p4

# ------------------------------------------- Tutorials ------------------------------------------- #
sudo pip3 install crcmod
git clone https://github.com/p4lang/tutorials

# sudo pip3 install p4runtime
# Do this last!
sudo reboot
