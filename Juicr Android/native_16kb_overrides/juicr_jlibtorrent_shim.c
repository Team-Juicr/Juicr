#include <jni.h>

// Compatibility shim for Juicr's 16 KB rebuilt jlibtorrent binaries.
//
// The current rebuilt libjlibtorrent-1.2.0.18.so is missing a small set of JNI
// wrappers that exist in FrostWire's Java surface. Juicr's P2P bridge does not
// depend on these specific optional flags/fields, but the generated Java static
// initializers require the symbols to exist before the useful torrent classes can
// load. Keep these stubs conservative: return null/zero defaults and no-op
// setters so the runtime can continue to the supported bridge path.

#define JUICR_JNI(name) Java_com_frostwire_jlibtorrent_swig_libtorrent_1jni_##name

JNIEXPORT jlong JNICALL JUICR_JNI(reannounce_1flags_1t_1all)(JNIEnv *env, jclass clazz) {
    (void)env;
    (void)clazz;
    return 0;
}

JNIEXPORT jboolean JNICALL JUICR_JNI(reannounce_1flags_1t_1nonZero)(JNIEnv *env, jclass clazz, jlong ptr, jobject self) {
    (void)env;
    (void)clazz;
    (void)ptr;
    (void)self;
    return JNI_FALSE;
}

JNIEXPORT jboolean JNICALL JUICR_JNI(reannounce_1flags_1t_1eq)(JNIEnv *env, jclass clazz, jlong a, jobject self_a, jlong b, jobject self_b) {
    (void)env;
    (void)clazz;
    (void)self_a;
    (void)self_b;
    return a == b ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL JUICR_JNI(reannounce_1flags_1t_1ne)(JNIEnv *env, jclass clazz, jlong a, jobject self_a, jlong b, jobject self_b) {
    (void)env;
    (void)clazz;
    (void)self_a;
    (void)self_b;
    return a != b ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jlong JNICALL JUICR_JNI(reannounce_1flags_1t_1or_1)(JNIEnv *env, jclass clazz, jlong a, jobject self_a, jlong b, jobject self_b) {
    (void)env;
    (void)clazz;
    (void)self_a;
    (void)self_b;
    return a | b;
}

JNIEXPORT jlong JNICALL JUICR_JNI(reannounce_1flags_1t_1and_1)(JNIEnv *env, jclass clazz, jlong a, jobject self_a, jlong b, jobject self_b) {
    (void)env;
    (void)clazz;
    (void)self_a;
    (void)self_b;
    return a & b;
}

JNIEXPORT jlong JNICALL JUICR_JNI(reannounce_1flags_1t_1xor)(JNIEnv *env, jclass clazz, jlong a, jobject self_a, jlong b, jobject self_b) {
    (void)env;
    (void)clazz;
    (void)self_a;
    (void)self_b;
    return a ^ b;
}

JNIEXPORT jlong JNICALL JUICR_JNI(reannounce_1flags_1t_1inv)(JNIEnv *env, jclass clazz, jlong ptr, jobject self) {
    (void)env;
    (void)clazz;
    (void)self;
    return ~ptr;
}

JNIEXPORT jint JNICALL JUICR_JNI(reannounce_1flags_1t_1to_1int)(JNIEnv *env, jclass clazz, jlong ptr, jobject self) {
    (void)env;
    (void)clazz;
    (void)self;
    return (jint)ptr;
}

JNIEXPORT jlong JNICALL JUICR_JNI(new_1reannounce_1flags_1t)(JNIEnv *env, jclass clazz) {
    (void)env;
    (void)clazz;
    return 0;
}

JNIEXPORT void JNICALL JUICR_JNI(delete_1reannounce_1flags_1t)(JNIEnv *env, jclass clazz, jlong ptr) {
    (void)env;
    (void)clazz;
    (void)ptr;
}

JNIEXPORT jlong JNICALL JUICR_JNI(announce_1endpoint_1get_1message)(JNIEnv *env, jclass clazz, jlong ptr, jobject self) {
    (void)env;
    (void)clazz;
    (void)ptr;
    (void)self;
    return 0;
}

JNIEXPORT jlong JNICALL JUICR_JNI(announce_1entry_1get_1url)(JNIEnv *env, jclass clazz, jlong ptr, jobject self) {
    (void)env;
    (void)clazz;
    (void)ptr;
    (void)self;
    return 0;
}

JNIEXPORT void JNICALL JUICR_JNI(announce_1entry_1set_1url)(JNIEnv *env, jclass clazz, jlong ptr, jobject self, jlong value_ptr, jobject value) {
    (void)env;
    (void)clazz;
    (void)ptr;
    (void)self;
    (void)value_ptr;
    (void)value;
}

JNIEXPORT jlong JNICALL JUICR_JNI(announce_1entry_1get_1trackerid)(JNIEnv *env, jclass clazz, jlong ptr, jobject self) {
    (void)env;
    (void)clazz;
    (void)ptr;
    (void)self;
    return 0;
}

JNIEXPORT void JNICALL JUICR_JNI(announce_1entry_1set_1trackerid)(JNIEnv *env, jclass clazz, jlong ptr, jobject self, jlong value_ptr, jobject value) {
    (void)env;
    (void)clazz;
    (void)ptr;
    (void)self;
    (void)value_ptr;
    (void)value;
}

JNIEXPORT void JNICALL JUICR_JNI(torrent_1status_1total_1set)(JNIEnv *env, jclass clazz, jlong ptr, jobject self, jlong value) {
    (void)env;
    (void)clazz;
    (void)ptr;
    (void)self;
    (void)value;
}

JNIEXPORT jlong JNICALL JUICR_JNI(torrent_1status_1total_1get)(JNIEnv *env, jclass clazz, jlong ptr, jobject self) {
    (void)env;
    (void)clazz;
    (void)ptr;
    (void)self;
    return 0;
}

JNIEXPORT jlong JNICALL JUICR_JNI(torrent_1handle_1clear_1disk_1cache_1get)(JNIEnv *env, jclass clazz) {
    (void)env;
    (void)clazz;
    return 0;
}

JNIEXPORT jlong JNICALL JUICR_JNI(torrent_1handle_1ignore_1min_1interval_1get)(JNIEnv *env, jclass clazz) {
    (void)env;
    (void)clazz;
    return 0;
}

JNIEXPORT void JNICALL JUICR_JNI(torrent_1handle_1force_1reannounce_1_1SWIG_13)(JNIEnv *env, jclass clazz, jlong ptr, jobject self) {
    (void)env;
    (void)clazz;
    (void)ptr;
    (void)self;
}

JNIEXPORT jint JNICALL JUICR_JNI(settings_1pack_1support_1share_1mode_1get)(JNIEnv *env, jclass clazz) {
    (void)env;
    (void)clazz;
    return 0;
}
