#!/usr/bin/env python3
"""
ChessSnap: Android Platform Configurator
Configures:
- AndroidManifest.xml (AdMob App ID, Impeller, Strips RECORD_AUDIO & External Storage)
- Gradle: Target SDK 36 (Android 16), Min SDK 23, Compile SDK 36
- Dynamic Release Signing: Decodes SIGNING_KEY_BASE64 from GitHub Secrets or uses persistent upload key
"""
import os
import glob
import re
import base64

print("[configure_android] Starting Android platform configuration...")

# 1. Resolve Keystore and Signing Credentials
signing_key_b64 = os.environ.get("SIGNING_KEY_BASE64", "").strip()
store_password = os.environ.get("KEY_STORE_PASSWORD", "").strip()
key_password = os.environ.get("KEY_PASSWORD", "").strip() or store_password
key_alias = os.environ.get("KEY_ALIAS", "").strip() or "chesssnap"

os.makedirs("android/app", exist_ok=True)
keystore_dest = "android/app/chesssnap-upload-key.jks"

if signing_key_b64:
    with open(keystore_dest, "wb") as f:
        f.write(base64.b64decode(signing_key_b64))
    print("[configure_android] Successfully decoded production upload keystore from GitHub Secret.")
elif os.path.exists(keystore_dest):
    print("[configure_android] Using existing keystore in android/app/")
else:
    # Generate temporary uncommitted keystore so CI build passes cleanly if secret is not set yet
    print("[configure_android] NOTICE: SIGNING_KEY_BASE64 secret not yet configured in GitHub.")
    print("[configure_android] Generating build keystore. Remember to add SIGNING_KEY_BASE64 to GitHub Secrets for store submission.")
    try:
        from cryptography import x509
        from cryptography.x509.oid import NameOID
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import rsa
        from cryptography.hazmat.primitives.serialization import pkcs12
        import datetime

        store_password = store_password or "chesssnap2026"
        key_password = key_password or store_password
        key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        subject = issuer = x509.Name([
            x509.NameAttribute(NameOID.COMMON_NAME, "ChessSnap Production"),
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, "ChessSnap AI"),
            x509.NameAttribute(NameOID.COUNTRY_NAME, "US"),
        ])
        now = datetime.datetime.now(datetime.timezone.utc)
        cert = (
            x509.CertificateBuilder()
            .subject_name(subject)
            .issuer_name(issuer)
            .public_key(key.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(now)
            .not_valid_after(now + datetime.timedelta(days=10000))
            .sign(key, hashes.SHA256())
        )
        p12 = pkcs12.serialize_key_and_certificates(
            name=key_alias.encode("utf-8"),
            key=key,
            cert=cert,
            cas=None,
            encryption_algorithm=serialization.BestAvailableEncryption(store_password.encode("utf-8"))
        )
        with open(keystore_dest, "wb") as f:
            f.write(p12)
        print("[configure_android] Generated CI signing keystore.")
    except Exception as e:
        print(f"[configure_android] Could not generate fallback keystore: {e}")

# Write key.properties for Gradle
store_password = store_password or "chesssnap2026"
key_password = key_password or store_password
props_content = f"""storePassword={store_password}
keyPassword={key_password}
keyAlias={key_alias}
storeFile=chesssnap-upload-key.jks
"""
with open("android/key.properties", "w") as f:
    f.write(props_content)
with open("android/app/key.properties", "w") as f:
    f.write(props_content)

# 2. Configure AndroidManifest.xml
admob_app_id = os.environ.get("ADMOB_APP_ID", "").strip() or "ca-app-pub-3940256099942544~3347511713"

for m in glob.glob("android/app/src/main/AndroidManifest.xml"):
    with open(m, "r", encoding="utf-8") as f:
        c = f.read()

    # Ensure xmlns:tools is declared in <manifest>
    if "xmlns:tools=" not in c:
        c = c.replace("<manifest", '<manifest xmlns:tools="http://schemas.android.com/tools"')

    # Permissions: declare only CAMERA and INTERNET. Explicitly strip unused permissions!
    perms = """    <uses-permission android:name="android.permission.CAMERA" />
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.RECORD_AUDIO" tools:node="remove" />
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" tools:node="remove" />
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" tools:node="remove" />
    <uses-feature android:name="android.hardware.camera" android:required="false" />
    <uses-feature android:name="android.hardware.camera.autofocus" android:required="false" />
"""
    if "android.permission.CAMERA" not in c:
        c = c.replace("<application", perms + "    <application")
    else:
        # Strip audio & storage if not already removed
        removals = ""
        if "RECORD_AUDIO" not in c:
            removals += '    <uses-permission android:name="android.permission.RECORD_AUDIO" tools:node="remove" />\n'
        if "READ_EXTERNAL_STORAGE" not in c:
            removals += '    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" tools:node="remove" />\n'
        if "WRITE_EXTERNAL_STORAGE" not in c:
            removals += '    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" tools:node="remove" />\n'
        if removals:
            c = c.replace("<application", removals + "    <application")

    # Metadata: AdMob APPLICATION_ID
    meta = f"""        <meta-data android:name="com.google.android.gms.ads.APPLICATION_ID" android:value="{admob_app_id}"/>\n"""
    if "APPLICATION_ID" not in c:
        c = c.replace("<activity", meta + "        <activity")
    else:
        c = re.sub(
            r'<meta-data\s+android:name="com\.google\.android\.gms\.ads\.APPLICATION_ID"\s+android:value="[^"]*"\s*/>',
            f'<meta-data android:name="com.google.android.gms.ads.APPLICATION_ID" android:value="{admob_app_id}"/>',
            c,
        )

    # Strip any EnableImpeller metadata (prevents slow Vulkan software warmup on emulators/devices)
    c = re.sub(
        r'\s*<meta-data\s+android:name="io\.flutter\.embedding\.android\.EnableImpeller"\s+android:value="[^"]*"\s*/>',
        '',
        c,
    )

    # App Label
    c = re.sub(r'android:label="[^"]*"', 'android:label="ChessSnap"', c)

    with open(m, "w", encoding="utf-8") as f:
        f.write(c)
    print(f"[configure_android] Updated {m} (AdMob configured, RECORD_AUDIO & storage stripped, Impeller stripped for fast cold start).")

# 3. Configure build.gradle / build.gradle.kts
groovy_signing = f"""    signingConfigs {{
        release {{
            keyAlias '{key_alias}'
            keyPassword '{key_password}'
            storeFile file('chesssnap-upload-key.jks')
            storePassword '{store_password}'
        }}
    }}
"""

kotlin_signing = f"""    signingConfigs {{
        create("release") {{
            keyAlias = "{key_alias}"
            keyPassword = "{key_password}"
            storeFile = file("chesssnap-upload-key.jks")
            storePassword = "{store_password}"
        }}
    }}
"""

for g in glob.glob("android/app/build.gradle*"):
    with open(g, "r", encoding="utf-8") as f:
        txt = f.read()

    is_kts = g.endswith(".kts")

    # Target Android 16 (API 36), Compile SDK 36, Min SDK 23
    txt = txt.replace("compileSdkVersion flutter.compileSdkVersion", "compileSdkVersion 36")
    txt = txt.replace("compileSdk = flutter.compileSdkVersion", "compileSdk = 36")
    txt = txt.replace("compileSdkVersion 35", "compileSdkVersion 36")
    txt = txt.replace("compileSdk = 35", "compileSdk = 36")

    txt = txt.replace("targetSdkVersion flutter.targetSdkVersion", "targetSdkVersion 36")
    txt = txt.replace("targetSdk = flutter.targetSdkVersion", "targetSdk = 36")
    txt = txt.replace("targetSdkVersion 35", "targetSdkVersion 36")
    txt = txt.replace("targetSdk = 35", "targetSdk = 36")

    txt = txt.replace("minSdkVersion flutter.minSdkVersion", "minSdkVersion 23")
    txt = txt.replace("minSdkVersion = flutter.minSdkVersion", "minSdkVersion = 23")
    txt = txt.replace("minSdkVersion 21", "minSdkVersion 23")
    txt = txt.replace("minSdkVersion = 21", "minSdkVersion 23")

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
    print(f"[configure_android] Configured TargetSdk 36, MinSdk 23 & Release Signing in {g}")

print("[configure_android] All configurations applied successfully!")
