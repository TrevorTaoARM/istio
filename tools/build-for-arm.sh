#!/bin/bash

set -x

CURR_DIR=$(dirname "${BASH_SOURCE[0]}")


#mkdir istio && cd istio &&

if [ ! -d ${CURR_DIR}/istio ]; then
    git clone https://github.com/istio/istio.git &&
    git clone https://github.com/istio/proxy.git &&
    git clone https://github.com/istio/tools.git
fi

#pushd istio && git checkout tools/docker && git apply ../patch/docker.patch && popd

# Build build-tools and build-tools-proxy
pushd ${CURR_DIR}/tools/docker/build-tools
if [ -z "$(docker images |grep "build-tools-proxy" | grep "master-latest")" ]; then 
    DRY_RUN=1 time ./build-and-push.sh
fi
popd

# Build Istio binary
pushd ${CURR_DIR}/istio
TARGET_ARCH=arm64 IMAGE_VERSION=master-latest make build
popd

pushd ${CURR_DIR}/proxy
export PROXY_REPO_SHA=$(git rev-parse HEAD)
popd

# Build Envoy and install envoy
if [ ! -f ${CURR_DIR}/istio/out/linux_arm64/release/envoy ]; then
    docker rm -f istio-proxy-build || true
    docker run --name istio-proxy-build -it -v $(realpath ${CURR_DIR}/proxy):/work -w /work -u $(id -u) gcr.io/istio-testing/build-tools-proxy:master-latest make build
    echo "Now copy envoy binary to release dir:"
    docker cp istio-proxy-build:/work/bazel-bin/src/envoy/envoy ${CURR_DIR}/istio/out/linux_arm64/release/envoy-${PROXY_REPO_SHA}
    #sudo chown $(id -u):$(id -u) ${CURR_DIR}/istio/out/linux_arm64
    cp ${CURR_DIR}/istio/out/linux_arm64/release/envoy-${PROXY_REPO_SHA} ${CURR_DIR}/istio/out/linux_arm64/release/envoy
fi 


export IMAGE_TAG=master-latest
export IMAGE_VERSION=$IMAGE_TAG
export DOCKER_ARCHITECTURES="linux/arm64"
export TARGETARCH="arm64"
export HUBS="gcr.io/istio-release"
export HUB=$HUBS
export TAG=$IMAGE_TAG
export BASE_VERSION=$IMAGE_TAG

export TARGET_ARCH=arm64
export CI=true
# Build Istio base containers
cd ${CURR_DIR}/istio

for i in 'dockerx.base' 'dockerx.distroless' 'dockerx.app_sidecar_base_ubuntu_xenial' 'dockerx.app_sidecar_base_ubuntu_bionic' 'dockerx.app_sidecar_base_ubuntu_focal' 'dockerx.app_sidecar_base_debian_9' 'dockerx.app_sidecar_base_debian_10' 'dockerx.app_sidecar_base_centos_8' 'dockerx.app_sidecar_base_centos_7'; do HUB="gcr.io/istio-release" TARGET_ARCH="arm64" make $i; done

# Build Istio core containers
for i in 'dockerx.pilot' 'dockerx.proxyv2' 'dockerx.app' 'dockerx.pilot' 'dockerx.install-cni' 'dockerx.istioctl' 'dockerx.operator'; do HUB="istio" make $i; done




