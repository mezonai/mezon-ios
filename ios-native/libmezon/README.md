# Mezon Protocol Library
This client library to work with mezon-quic cross platform

## Build in WIN32

### Build Mezon Library

Clean build folder first to avoid cache conflicts
```
rd /s /q build_win
mkdir build_win
cd build_win
```

Use the 2019 Generator
```
cmake -G "Visual Studio 16 2019" -A x64 ..

cmake --build . --config Release
```

## Build in LINUX

### Build Mezon Library

Clean build folder first to avoid cache conflicts
```
rm -rf build
mkdir build
cd build
```

Run cmake
```
cmake ..

cmake --build . --config Release
```

CHANGE: mezon_native.target.mk

For Android (arm64-v8a):
```
mkdir build_android && cd build_android
cmake .. \
  -DCMAKE_TOOLCHAIN_FILE=$NDK_ROOT/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-26

make -j$(nproc)

```

For iOS (Device):
```
mkdir build_ios && cd build_ios
cmake .. \
  -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_XCODE_ATTRIBUTE_IPHONEOS_DEPLOYMENT_TARGET=14.0
cmake --build . --config Release
```

