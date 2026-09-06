# tflite_flutter references TensorFlow Lite's optional GPU delegate, which this
# app does not bundle - the scan screen runs SSD MobileNet on the CPU delegate.
# R8 treats the dangling reference as an error rather than a warning and fails
# the release build outright, so the two classes it names are silenced here.
# These are the rules the Android Gradle plugin itself generated into
# build/app/outputs/mapping/release/missing_rules.txt.
-dontwarn org.tensorflow.lite.gpu.GpuDelegateFactory$Options$GpuBackend
-dontwarn org.tensorflow.lite.gpu.GpuDelegateFactory$Options

# The interpreter is reached over JNI, so R8 cannot see those uses and would be
# free to strip or rename the classes the native side looks up by name.
-keep class org.tensorflow.lite.** { *; }
