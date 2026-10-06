# Called from the native Mihomo bridge (JNI) by name, so R8 must keep it.
-keepclassmembers class net.usekago.app.KaGoVpnService {
    java.lang.String resolvePackage(int, java.lang.String, int, java.lang.String, int);
}
