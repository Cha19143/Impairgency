# tflite_flutter references TensorFlow Lite's optional GPU delegate, which this
# app does not bundle - the scan screen runs YOLO11n on the CPU delegate.
# R8 treats the dangling reference as an error rather than a warning and fails
# the release build outright, so the two classes it names are silenced here.
# These are the rules the Android Gradle plugin itself generated into
# build/app/outputs/mapping/release/missing_rules.txt.
-dontwarn org.tensorflow.lite.gpu.GpuDelegateFactory$Options$GpuBackend
-dontwarn org.tensorflow.lite.gpu.GpuDelegateFactory$Options

# The interpreter is reached over JNI, so R8 cannot see those uses and would be
# free to strip or rename the classes the native side looks up by name.
-keep class org.tensorflow.lite.** { *; }

# google_mlkit_text_recognition can drive five scripts and references the
# options class for each, but only the Latin recogniser is declared as a
# dependency - the other four are separate artifacts this app does not ship,
# because a medicine label in the Philippines is Latin script. The same R8
# behaviour as the GPU delegate above: a dangling reference is an error, and
# the release build fails. These are the rules from missing_rules.txt.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Firebase finds its SDK modules by reflection: each ships a ComponentRegistrar
# that FirebaseInitProvider instantiates through its no-argument constructor.
# firebase-components' own consumer rule keeps the classes but, under AGP 9's
# R8, not that constructor - so on a fresh install the release build logged
# "Could not instantiate CrashlyticsRegistrar ... NoSuchMethodException <init>",
# the first Crashlytics call threw "component is not present" from main(),
# and the app never left the splash screen. Keep the constructor too.
-keep class * implements com.google.firebase.components.ComponentRegistrar { <init>(); }
