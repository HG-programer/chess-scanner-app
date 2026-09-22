#!/usr/bin/env python3
"""
ChessSnap: Android Platform Configurator
Configures AndroidManifest.xml, Gradle release signing, minSdk 23, Impeller, and Strips RECORD_AUDIO.
"""
import os
import glob
import re
import shutil

print("[configure_android] Starting Android platform configuration...")

# 1. Copy Keystore and key.properties into android/app and android/
keystore_src = os.path.join("keystore", "chesssnap-upload-key.jks")
props_src = os.path.join("keystore", "key.properties")

if os.path.exists(keystore_src):
    os.makedirs("android/app", exist_ok=True)
    shutil.copy2(keystore_src, "android/app/chesssnap-upload-key.jks")
    print("[configure_android] Copied chesssnap-upload-key.jks to android/app/")
else:
    print(f"[configure_android] WARNING: {keystore_src} not found!")

if os.path.exists(props_src):
    shutil.copy2(props_src, "android/key.properties")
    shutil.copy2(props_src, "android/app/key.properties")
    print("[configure_android] Copied key.properties to android/ and android/app/")

# 2. Configure AndroidManifest.xml
admob_app_id = os.environ.get("ADMOB_APP_ID", "").strip() or "ca-app-pub-3940256099942544~3347511713"

for m in glob.glob("android/app/src/main/AndroidManifest.xml"):
    with open(m, "r", encoding="utf-8") as f:
        c = f.read()

    # Ensure xmlns:tools is declared in <manifest>
    if "xmlns:tools=" not in c:
        c = c.replace("<manifest", '<manifest xmlns:tools="http://schemas.android.com/tools"')

    # Permissions (explicitly remove unused RECORD_AUDIO pulled from camera plugin)
    perms = """    <uses-permission android:name="android.permission.CAMERA" />
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.RECORD_AUDIO" tools:node="remove" />
    <uses-feature android:name="android.hardware.camera" android:required="false" />
    <uses-feature android:name="android.hardware.camera.autofocus" android:required="false" />
"""
    if "android.permission.CAMERA" not in c:
        c = c.replace("<application", perms + "    <application")
    elif "android.permission.RECORD_AUDIO" not in c:
        c = c.replace("<application", '    <uses-permission android:name="android.permission.RECORD_AUDIO" tools:node="remove" />\n    <application')

    # Metadata: AdMob APPLICATION_ID & Impeller
    meta = f"""        <meta-data android:name="com.google.android.gms.ads.APPLICATION_ID" android:value="{admob_app_id}"/>
        <meta-data android:name="io.flutter.embedding.android.EnableImpeller" android:value="true"/>
"""
    if "APPLICATION_ID" not in c:
        c = c.replace("<activity", meta + "        <activity")
    else:
        c = re.sub(
            r'<meta-data\s+android:name="com\.google\.android\.gms\.ads\.APPLICATION_ID"\s+android:value="[^"]*"\s*/>',
            f'<meta-data android:name="com.google.android.gms.ads.APPLICATION_ID" android:value="{admob_app_id}"/>',
            c,
        )
        if "EnableImpeller" not in c:
            c = c.replace("<activity", '        <meta-data android:name="io.flutter.embedding.android.EnableImpeller" android:value="true"/>\n        <activity')

    # App Label
    c = re.sub(r'android:label="[^"]*"', 'android:label="ChessSnap"', c)

    with open(m, "w", encoding="utf-8") as f:
        f.write(c)
    print(f"[configure_android] Updated {m} with AdMob ID ({admob_app_id[:22]}...), Impeller enabled, and RECORD_AUDIO removed.")

# 3. Configure build.gradle / build.gradle.kts
groovy_signing = """    signingConfigs {
        release {
            keyAlias 'chesssnap'
            keyPassword 'chesssnap2026'
            storeFile file('chesssnap-upload-key.jks')
            storePassword 'chesssnap2026'
        }
    }
"""

kotlin_signing = """    signingConfigs {
        create("release") {
            keyAlias = "chesssnap"
            keyPassword = "chesssnap2026"
            storeFile = file("chesssnap-upload-key.jks")
            storePassword = "chesssnap2026"
        }
    }
"""

for g in glob.glob("android/app/build.gradle*"):
    with open(g, "r", encoding="utf-8") as f:
        txt = f.read()

    is_kts = g.endswith(".kts")

    # Bump minSdkVersion to 23 (Android 6.0 Marshmallow)
    txt = txt.replace("minSdkVersion flutter.minSdkVersion", "minSdkVersion 23")
    txt = txt.replace("minSdkVersion = flutter.minSdkVersion", "minSdkVersion = 23")
    txt = txt.replace("minSdkVersion 21", "minSdkVersion 23")
    txt = txt.replace("minSdkVersion = 21", "minSdkVersion = 23")

    # Configure release signing with upload keystore
    if is_kts:
        if "signingConfigs {" not in txt:
            txt = txt.replace("buildTypes {", kotlin_signing + "    buildTypes {")
        txt = txt.replace('signingConfig = signingConfigs.debug', 'signingConfig = signingConfigs.getByName("release")')
        txt = txt.replace('signingConfig = signingConfigs.getByName("debug")', 'signingConfig = signingConfigs.getByName("release")')
    else:
        if "signingConfigs {" not in txt:
            txt = txt.replace("buildTypes {", groovy_signing + "    buildTypes {")
        txt = txt.replace("signingConfig signingConfigs.debug", "signingConfig signingConfigs.release")
        txt = txt.replace("signingConfig = signingConfigs.debug", "signingConfig = signingConfigs.release")

    with open(g, "w", encoding="utf-8") as f:
        f.write(txt)
    print(f"[configure_android] Configured release signing & minSdk 23 in {g}")

print("[configure_android] All configurations applied successfully!")
