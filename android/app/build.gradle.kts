plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.flutter_suscripciones"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications usa APIs de fechas de Java 8+ que en
        // Android viejos se agregan con "desugaring".
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.flutter_suscripciones"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Dos versiones de la app (ver docs/deteccion.md, "Versiones completa y sinSms"):
    //  - completa: incluye "Buscar suscripciones en mis SMS" (READ_SMS, declarado
    //    solo en src/completa/AndroidManifest.xml).
    //  - sinSms: sin READ_SMS ni el lector del historial (src/sinSms). Conserva el
    //    lector de notificaciones, el registro manual y "Compartir".
    // Las dos usan el mismo applicationId: se instala una u otra, no ambas.
    // flutter run / flutter build sin --flavor usan "completa" (default-flavor
    // en pubspec.yaml).
    flavorDimensions += "sms"
    productFlavors {
        create("completa") { dimension = "sms" }
        create("sinSms") { dimension = "sms" }
    }

    buildTypes {
        release {
            // Para la entrega del proyecto el APK release se firma con la llave
            // de debug (se instala en el celular sin problema). Para publicar
            // en Play Store haría falta una llave propia; no se configura.
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Tarea de fondo: procesar la cola con la app cerrada (ProcesarColaWorker).
    implementation("androidx.work:work-runtime-ktx:2.10.1")
    // Tests del filtro nativo (src/test): corren en el PC, sin celular.
    // org.json real, porque el de Android en los tests de JVM es solo un esqueleto.
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}
