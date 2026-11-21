# Spotify Android (base.apk) — Reverse Engineering Breakdown

> Source artifact: `C:\Users\PIYAS\Downloads\com.spotify.music_9.1.80.2221-145767611_4arch_7dpi_25lang_3feat_5daa4b1dea1cc8546155eed363bef99a_apkmirror.com.apkm`
> Extracted bundle: `C:\Users\PIYAS\AppData\Local\Temp\opencode\spotify-apk\`
> Base APK: `C:\Users\PIYAS\AppData\Local\Temp\opencode\spotify-apk\base.apk`
> Base APK sha256: `3dc0c561236d4dc01c17acc12dd219914fa2de61992a3d1428ff6ee677cd45ee`
> Format: APK (zip), 93,967,011 bytes (base); version 9.1.80.2221 (code 145767611)
> Analysis tool: REA (static inventory) + direct extraction + Python string extraction
> Date: 2026-11-17

## 0. Scope & method

JADX decompilation is NOT available (REA_JADX_MCP_JAR not configured), so Java/Kotlin source
is not recovered. Analysis is limited to:
- APK container inventory (REA inspect_artifact)
- Binary string extraction from `classes.dex` (Python, min length 8, filtered)
- Extracted resource/manifest bytes (binary XML; not decoded)
- Property files, assets listing

Confidence labels: Observed / Inferred / Unknown.

---

## 1. Artifact identity & integrity

| Field | Value |
|---|---|
| Container (.apkm) | zip of split APKs |
| Base APK | `base.apk`, 93,967,011 bytes |
| Base APK sha256 | `3dc0c561236d4dc01c17acc12dd219914fa2de61992a3d1428ff6ee677cd45ee` |
| REA format | `apk` |
| REA integrity contradictions | 0 |
| Inventory nodes | 4088 |
| Inventory occurrences | 4211 |
| Inventory edges | 4210 |
| Source complete | true (container-entries scope) |

Split APKs present: base, split_config (arch: x86/x86_64/arm64-v8a/armeabi-v7a),
split_config (lang: ar, de, en, es, fr, hi, hu, iw, it, ja, ko, pl, pt, ru, th, tr, uk, vi, zh),
split_config (features: audiomodelimpl, engage-core, etc.).

---

## 2. Package layout (Observed)

Top-level entries in base.apk:
- `AndroidManifest.xml` (141,492 bytes, binary XML)
- `classes.dex` … `classes13.dex` (14 dex files; largest ~9.97 MB)
- `resources.arsc`
- `assets/` (licenses, TZDB, PublicSuffixDatabase, crashlytics, dexopt profiles, etc.)
- `res/`
- `kotlin/`, `org/`, `proguard/`, `META-INF/`
- `billing.properties`, `common.properties`, `core-common.properties`, `crossdeviceprompt.properties`,
  `engage-core.properties`, `feature-delivery.properties`, `firebase-encoders-proto.properties`,
  `googleid.properties`, `image.properties`, `integrity.properties`, `meet-addons.properties`,
  `play-services-*.properties`, `recaptcha.properties`, `vision-*.properties`, `car-app-api.level`

---

## 3. Architecture (Inferred + Observed)

### 3.1 Stack
- **Kotlin + AndroidX + Jetpack Compose likely** (observed: `kotlin.reflect.jvm.internal.impl`, `kotlinx.coroutines`,
  `kotlinx.serialization`, `androidx.xr.runtime.interfaces.XrDeviceCapabilityProviderFactory`).
- **Mobius** state management (observed strings: `com/spotify/mobius/Connectable`, `EventSource`, `MobiusHooks`,
  `RxMobius`, `com/spotify/mobius/coroutines`).
- **Coroutines** (`kotlinx.coroutines.CoroutineExceptionHandler`, `MainDispatcherFactory`).
- **Dependency injection** via service files (META-INF/services) — Jackson, Kotlin reflection, Mobius, etc.
- **Firebase Crashlytics** (`crashlytics-build.properties`).
- **Google Play Services** (auth, base, basement, tasks, location, maps, cast, ML kit, recaptcha).
- **Billing** (`billing.properties`).
- **Car app** (`car-app-api.level`) — Android Auto support.

### 3.2 Multi-module / feature delivery
- Split APKs per language and architecture → dynamic feature delivery (Play Feature Delivery).
- `feature-delivery.properties` present.

---

## 4. Search feature (Observed strings)

Extracted from `classes.dex` (min length 8, filtered). Representative search-related strings:

- `spotify:search` (inferred URI scheme for search)
- Recent searches / search history referenced (inferred from desktop parity; Android strings include search-related mobius components)
- Search navigation likely via deep links `spotify:search`.

Observed package paths (from dex strings):
- `com/spotify/eventsender/...` (analytics/event sender)
- `com/spotify/mobius/...` (state management)
- `com/spotify/bootstrap/v1/proto/...`
- `com/spotify/core/core/DeviceType`
- `com/spotify/cosmos/cosmos/Router`
- `com/spotify/player/model/Context`
- `com/spotify/recap/RecapExtension`
- `com/spotify/upsells/v1/proto/CTA`
- `com/spotify/idj/v1/BodySection`, `Description` (Home/IDJ surface)
- `speechless/v1/hierarchy/settings`
- `spotify:collection:your-episodes`
- `spotify:audiobook:consumptioncap`

Note: exact search input/activity/fragment class names are obfuscated in release dex (R8/ProGuard). Readable identifiers are limited to keep-package names and proto classes.

### 4.1 Android navigation (Observed)
- Fragments heavily used: strings reference `Fragment`, `FragmentManager`, `FragmentTransaction`,
  `registerForActivityResult`, `not attached to Activity`.
- Likely Activity/Fragment-based navigation with deep links.

---

## 5. Home UI (Observed strings)

- `!HOME_LOGGING_SPAN_ID_FIELD_NUMBER` → protobuf field for home logging span id.
- `com/spotify/idj/v1/BodySection`, `Description` → IDJ (In-app discovery?) home sections.
- `spotify:collection:your-episodes` → collection entry point.
- `getTotalUserUnseenActivityEvents` → activity feed (friend activity / "what's new").
- `spotify.ads.esperanto.proto.Slots`, `State` → ads slots on home.
- `ReachabilityMonitorConnectionApis` → network reachability for home feed.

Home feed composition and personalization RPCs are not recoverable (Unknown).

---

## 6. Settings (Observed strings)

- `speechless/v1/hierarchy/settings` → settings hierarchy endpoint (protobuf).
- `Settings$Global`, `Settings$Secure` (Android system settings reads).
- `Usage of deprecated settings URI` → settings deep links.
- `setOfflineFlushEndpointUrlNative` → offline flush endpoint config.
- `setAppNativeLogin5SetupLifecycle`, `getAppNativeLogin5SetupLifecycle`.

---

## 7. Feature flags / experiments (Observed)

- `common.properties`, `core-common.properties`, `crossdeviceprompt.properties`, `engage-core.properties`.
- `feature-delivery.properties` → Play Feature Delivery flags.
- `integrity.properties` → app integrity checks.
- `rcs_overrides.json` (assets) → RCS overrides.

Specific flag keys not extracted (binary/protobuf, Unknown).

---

## 8. Networking / backend (Observed strings)

- `X-Crashlytics-API-Client-Version` → Crashlytics API.
- `SetPreferredIncarnation endpoint` → endpoint incarnation selection.
- `setOfflineFlushEndpointUrlNative` → offline endpoint.
- `spotify:audiobook:consumptioncap` → audiobook consumption cap URI.
- Cosmos router referenced: `com/spotify/cosmos/cosmos/Router`.
- Esperanto protobufs: `spotify.ads.esperanto.proto.*`.

Exact REST/gRPC endpoints, auth scheme, and payload shapes are not in readable strings (Unknown — likely protobuf + internal cosmos).

---

## 9. Storage / persistence (Observed)

- `assets/dexopt/baseline.prof`, `baseline.profm` → ART baseline profiles.
- `PublicSuffixDatabase.list` → networking.
- `TZDB.dat` → timezone data.
- Local preferences likely via SharedPreferences/DataStore (not visible in strings).

---

## 10. Ads (Observed)

- `spotify.ads.esperanto.proto.Slots`, `State`.
- `"Error fetching ad from InStreamApi"`.
- `"?loadingPlaceholder=pageApiDefault"`.

---

## 11. Car / Wear (Observed)

- `car-app-api.level`.
- `play-services-wearable.properties`.
- Android Auto / Wear OS support present.

---

## 12. UI/UX inventory (Observed)

- Compose vs Views: strings reference both `Fragment`/`FragmentManager` and possibly Compose (androidx.xr). Layout details (colors, spacing) are in binary resources (`resources.arsc`, `res/`) — not decoded (Unknown without aapt/JADX).
- Icons/drawables in `res/` (not enumerated here).

---

## 13. Permissions / manifest (Unknown)

`AndroidManifest.xml` is binary XML (141,492 bytes). Without aapt/JADX it is not decoded here.
Permissions, activities, services, receivers, deep-link intent-filters are Unknown from this pass.

---

## 14. Evidence index (REA)

| Evidence id | Operation | Subject | Notes |
|---|---|---|---|
| `ev_d92749ba02ebca3082c2972a8a0a58b3f415c7f67f849c0eee4d5af40e006292` | inspect_artifact | base.apk | parent; 4211 occurrences |
| `ev_3776964a5c2b74c9b48f5f4dff3bf8b91d7aa45bd9cd06cdc0930a674fbb446a` | inspect_analysis_view (summary) | base.apk | complete-within-view |
| `ev_d928c5d659ef2ff30bea20dab1942348f2a51487ed0e97dd6ff09e39a3476f66` | inspect_analysis_view (inventory, page 0) | base.apk | 40 of 4211 |

Direct evidence: Python string extraction from `classes.dex` → 2925 unique filtered strings saved to
`C:\Users\PIYAS\AppData\Local\Temp\opencode\dex_strings.txt`.

---

## 15. Unknowns consolidated (Android)

1. Java/Kotlin source (JADX not configured) — classes not decompiled.
2. AndroidManifest (binary XML not decoded) — permissions/activities/services/deep-links.
3. resources.arsc / res/ — layouts, drawables, colors, dimensions.
4. Search input/activity/fragment class names (obfuscated).
5. Server RPC endpoints, auth, payload shapes (protobuf + cosmos, not readable).
6. Settings key set.
7. Home feed personalization algorithm.
8. Storage backend details (SharedPreferences/DataStore/Room DBs).

---

## 16. Limitations

- No JADX → no decompiled source; only binary strings + container inventory.
- No aapt → no decoded manifest/resources.
- Static only; app never executed.
- Release build is R8/ProGuard obfuscated → most class names unreadable.
- Split APKs (arch/lang/feature) not individually analyzed; only base.apk.

## Appendix A — Full filtered string sample (classes.dex)

Total filtered strings: 403

- ��2 9 2 5 
-  
-    ( i s P r o v i d e d B y S p o t i f y = 
-  
-    I n v a l i d   S p o t i f y   a p p l i c a t i o n   i d :   
-  
-    L c o m / s p o t i f y / e v e n t s e n d e r / g a b o / a ; 
-  
-    L c o m / s p o t i f y / e v e n t s e n d e r / g a b o / b ; 
-  
-    L c o m / s p o t i f y / e v e n t s e n d e r / g a b o / c ; 
-  
-    L c o m / s p o t i f y / e v e n t s e n d e r / g a b o / d ; 
-  
-    L c o m / s p o t i f y / h o v e r c r a f t a s r / v 1 / a ; 
-  
-    L c o m / s p o t i f y / h o v e r c r a f t a s r / v 1 / b ; 
-  
-    L c o m / s p o t i f y / h o v e r c r a f t a s r / v 1 / d ; 
-  
-    L c o m / s p o t i f y / i d j / v 1 / B o d y S e c t i o n ; 
-  
-    L c o m / s p o t i f y / i d j / v 1 / D e s c r i p t i o n ; 
-  
-    L c o m / s p o t i f y / m o b i u s / C o n n e c t a b l e ; 
-  
-    L c o m / s p o t i f y / m o b i u s / E v e n t S o u r c e ; 
-  
-    L c o m / s p o t i f y / m o b i u s / M o b i u s H o o k s ; 
-  
-    L o c a l   F r a g m e n t M a n a g e r C o n t r o l l e r   
-  
-    S e t P r e f e r r e d I n c a r n a t i o n   e n d p o i n t 
-  
-    S p o t i f y   h a s   l e g a l   o b l i g a t i o n s   t o   r e p o r t   c o n s u m p t i o n .   I f   u n s u r e ,   r e a c h   o u t   t o   # s t r e a m - r e p o r t i n g - s u p p o r t   i n   S l a c k . 
-  
-    X - C r a s h l y t i c s - A P I - C l i e n t - V e r s i o n 
-  
-    d e c l a r e d   t a r g e t   f r a g m e n t   
-  
-    f o r   f r a g m e n t   
-  
-    f r a g m e n t   =   
-  
-    g e t A p p N a t i v e L o g i n 5 S e t u p L i f e c y c l e 
-  
-    g e t T o t a l U s e r U n s e e n A c t i v i t y E v e n t s 
-  
-    i s   a t t e m p t i n g   t o   r e g i s t e r F o r A c t i v i t y R e s u l t   a f t e r   b e i n g   c r e a t e d .   F r a g m e n t s   m u s t   c a l l   r e g i s t e r F o r A c t i v i t y R e s u l t ( )   b e f o r e   t h e y   a r e   c r e a t e d   ( i . e .   i n i t i a l i z a t i o n ,   o n A t t a c h ( ) ,   o r   o n C r e a t e ( ) ) . 
-  
-    n o t   a t t a c h e d   t o   A c t i v i t y 
-  
-    n o t   a t t a c h e d   t o   a n   a c t i v i t y . 
-  
-    s e t A p p N a t i v e L o g i n 5 S e t u p L i f e c y c l e 
-  
-    s e t O f f l i n e F l u s h E n d p o i n t U r l N a t i v e 
-  
-    s p e e c h l e s s / v 1 / h i e r a r c h y / s e t t i n g s 
-  
-    s p o t i f y : a u d i o b o o k : c o n s u m p t i o n c a p 
-  
-    s p o t i f y : c o l l e c t i o n : y o u r - e p i s o d e s 
-  
-    w i t h   a n o t h e r   f r a g m e n t   f o r   
-  
-  ! H O M E _ L O G G I N G _ S P A N _ I D _ F I E L D _ N U M B E R 
-  
-  ! L a n d r o i d / a p p / F r a g m e n t T r a n s a c t i o n ; 
-  
-  ! L a n d r o i d / c o n t e n t / D i a l o g I n t e r f a c e ; 
-  
-  ! L a n d r o i d / c o n t e n t / p m / A c t i v i t y I n f o ; 
-  
-  ! L c o m / s p o t i f y / m o b i u s / c o r o u t i n e s / a ; 
-  
-  ! L c o m / s p o t i f y / m o b i u s / c o r o u t i n e s / b ; 
-  
-  ! L c o m / s p o t i f y / m o b i u s / r x 3 / R x M o b i u s ; 
-  
-  ! R e a c h a b i l i t y M o n i t o r C o n n e c t i o n A p i s 
-  
-  ! a n d r o i d : s u p p o r t : s p o t i f y : f r a g m e n t s 
-  
-  ! g e t S c i o n F r o n t e n d A p i I m p l e m e n t a t i o n 
-  
-  ! s p o t i f y . a d s . e s p e r a n t o . p r o t o . S l o t s 
-  
-  ! s p o t i f y . a d s . e s p e r a n t o . p r o t o . S t a t e 
-  
-  " ? l o a d i n g P l a c e h o l d e r = p a g e A p i D e f a u l t 
-  
-  " E r r o r   f e t c h i n g   a d   f r o m   I n S t r e a m A p i 
-  
-  " F r a g m e n t M a n a g e r   h a s   b e e n   d e s t r o y e d 
-  
-  " L a n d r o i d / p r o v i d e r / S e t t i n g s $ G l o b a l ; 
-  
-  " L a n d r o i d / p r o v i d e r / S e t t i n g s $ S e c u r e ; 
-  
-  " L c o m / s p o t i f y / b o o t s t r a p / v 1 / p r o t o / a ; 
-  
-  " L c o m / s p o t i f y / b o o t s t r a p / v 1 / p r o t o / d ; 
-  
-  " L c o m / s p o t i f y / b o o t s t r a p / v 1 / p r o t o / e ; 
-  
-  " L c o m / s p o t i f y / b o o t s t r a p / v 1 / p r o t o / f ; 
-  
-  " L c o m / s p o t i f y / c o r e / c o r e / D e v i c e T y p e ; 
-  
-  " L c o m / s p o t i f y / c o s m o s / c o s m o s / R o u t e r ; 
-  
-  " L c o m / s p o t i f y / e v e n t s e n d e r / F r a g m e n t ; 
-  
-  " L c o m / s p o t i f y / p l a y e r / m o d e l / C o n t e x t ; 
-  
-  " L c o m / s p o t i f y / r e c a p / R e c a p E x t e n s i o n ; 
-  
-  " L c o m / s p o t i f y / u p s e l l s / v 1 / p r o t o / C T A ; 
-  
-  " U s a g e   o f   d e p r e c a t e d   s e t t i n g s   U R I :   
-  
-  " a u t h _ a p i _ c r e d e n t i a l s _ b e g i n _ s i g n _ i n 
-  
-  " a u t h _ a p i _ c r e d e n t i a l s _ r e v o k e _ a c c e s s 
-  
-  " a u t h _ a p i _ c r e d e n t i a l s _ s a v e _ p a s s w o r d 
-  
-  " i s H t t p R e d i r e c t C a c h i n g E n a b l e d N a t i v e 
-  
-  " r e g i s t e r A c t i v i t y L i f e c y c l e C a l l b a c k s 
-  
-  " s p o t i f y . a d s . e s p e r a n t o . p r o t o . E v e n t s 
-  
-  " s p o t i f y : i n t e r n a l : m u l t i - s o n g - t r a c k : 
-  
-  " s p o t i f y : u s e r : ( [ a - z A - Z 0 - 9 % _ ~ + . \ - ] + ) 
-  
-  #   i s   n o t   a s s o c i a t e d   w i t h   a   F r a g m e n t . 
-  
-  # A c t i v i t y   n o t   f o u n d   w h i l e   l a u n c h i n g   
-  
-  # L c o m / a n d r o i d / i n s t a l l r e f e r r e r / a p i / a ; 
-  
-  # L c o m / a n d r o i d / i n s t a l l r e f e r r e r / a p i / b ; 
-  
-  # L c o m / s p o t i f y / c o r e / h t t p / H t t p O p t i o n s ; 
-  
-  # L c o m / s p o t i f y / c o r e / h t t p / H t t p R e q u e s t ; 
-  
-  # L c o m / s p o t i f y / c o s m o s / c o s m o s / R e q u e s t ; 
-  
-  # L c o m / s p o t i f y / j v m / j n i / N a t i v e H e l p e r s ; 
-  
-  # S h o w   n o t i f i c a t i o n   s e t t i n g s   f r a g m e n t 
-  
-  # h t t p s : / / s b . s c o r e c a r d r e s e a r c h . c o m / p 2 
-  
-  # s p o t i f y : i n t e r n a l : a r t i s t - a t t r i b u t i o n 
-  
-  # s p o t i f y _ m i x _ u i _ t i t l e _ a r a b _ e x t r a b o l d 
-  
-  # s p o t i f y _ m i x _ u i _ t i t l e _ c y r l _ e x t r a b o l d 
-  
-  # s p o t i f y _ m i x _ u i _ t i t l e _ g r e k _ e x t r a b o l d 
-  
-  # s p o t i f y _ m i x _ u i _ t i t l e _ h e b r _ e x t r a b o l d 
-  
-  # s p o t i f y _ m i x _ u i _ t i t l e _ t h a i _ e x t r a b o l d 
-  
-  # w e a r _ s e t _ c l o u d _ s y n c _ s e t t i n g _ b y _ n o d e 
-  
-  $ ( ) L c o m / s p o t i f y / c o s m o s / c o s m o s / R o u t e r ; 
-  
-  $ L c o m / s p o t i f y / c o n n e c t i v i t y / S c h e d u l e r ; 
-  
-  $ L c o m / s p o t i f y / c o n t e x t s / D e v i c e A n d r o i d ; 
-  
-  $ L c o m / s p o t i f y / c o r e / h t t p / H t t p R e s p o n s e ; 
-  
-  $ L c o m / s p o t i f y / c o s m o s / c o s m o s / L i f e t i m e ; 
-  
-  $ L c o m / s p o t i f y / c o s m o s / c o s m o s / R e s p o n s e ; 
-  
-  $ P U B L I S H E D _ O N _ S P O T I F Y _ A T _ F I E L D _ N U M B E R 
-  
-  $ S e t t i n g   R o u t e   D i s c o v e r y   f o r   a p p I d s :   
-  
-  $ S e t t i n g   t h e   A P I   o p t i o n s   i s   r e q u i r e d . 
-  
-  $ S p o t i f y S e r v i c e :   D e l e t i n g   s t a t e   f i l e s 
-  
-  $ a r t i s t _ c o n t e x t _ m e n u _ p a g e _ a p i _ e n a b l e d 
-  
-  $ a u t h o r _ c o n t e x t _ m e n u _ p a g e _ a p i _ e n a b l e d 
-  
-  $ c o r e T h r e a d i n g A p i 
-  
-  $ s p o t i f y . a d s . e s p e r a n t o . p r o t o . S e t t i n g s 
-  
-  $ s p o t i f y : g e n r e : 0 J Q 5 D A u d k N j C g Y M M 0 T Z X D w 
-  
-  $ s p o t i f y : i n t e r n a l : a l l b o a r d i n g : o r i g i n : 
-  
-  $ s p o t i f y : s i t e m o d a l : w a t c h f e e d - f a l l b a c k 
-  
-  $ u n r e g i s t e r A c t i v i t y L i f e c y c l e C a l l b a c k s 
-  
-  % ( L c o m / s p o t i f y / c o s m o s / c o s m o s / R o u t e r ; ) V 
-  
-  % :   c o u l d   n o t   f i n d   F r a g m e n t   c o n s t r u c t o r 
-  
-  % L c o m / s p o t i f y / a g e n t g a t e w a y / v 1 / M e s s a g e ; 
-  
-  % L c o m / s p o t i f y / c a s i t a / v 1 / r e s o l v e d / I t e m ; 
-  
-  % L c o m / s p o t i f y / c o n t e n t a g n o s t i c / v 2 / Y e a r ; 
-  
-  % L c o m / s p o t i f y / c o n t e x t s / I n s t a l l a t i o n I d ; 
-  
-  % L c o m / s p o t i f y / c o n t e x t s / M o n o t o n i c C l o c k ; 
-  
-  % L c o m / s p o t i f y / c o r e / h t t p / C r o n e t R u n t i m e ; 
-  
-  % L c o m / s p o t i f y / l e x i c o n / d j / v 1 / D J P e r s o n a ; 
-  
-  % L c o m / s p o t i f y / m d a t a / e s p e r a n t o / p r o t o / a ; 
-  
-  % L c o m / s p o t i f y / m d a t a / e s p e r a n t o / p r o t o / b ; 
-  
-  % L c o m / s p o t i f y / m d a t a / e s p e r a n t o / p r o t o / e ; 
-  
-  % L c o m / s p o t i f y / p l a y e r / m o d e l / P l a y O r i g i n ; 
-  
-  % S U P P O R T S _ P L A Y L I S T _ M I X I N G _ F I E L D _ N U M B E R 
-  
-  % c o m . f a c e b o o k . i n t e r n a l . A P P _ S E T T I N G S . % s 
-  
-  % s p e e c h l e s s / v 1 / h i e r a r c h y / s e t t i n g s / m u t e 
-  
-  % s p o t i f y . a d s . e s p e r a n t o . p r o t o . T a r g e t i n g 
-  
-  % s p o t i f y : s i t e m o d a l : w a t c h f e e d - f a l l b a c k ? 
-  
-  % u s a g e _ a n d _ d i a g n o s t i c s _ s e t t i n g s _ a c c e s s 
-  
-  & ( L c o m / s p o t i f y / c o s m o s / c o s m o s / R e q u e s t ; ) V 
-  
-  & A l i g n e d C u r a t i o n . u s e r H a s C r e a t e d P l a y l i s t 
-  
-  & A u t h . A p i . I d e n t i t y . C r e d e n t i a l S a v i n g . A P I 
-  
-  & C a n ' t   c h a n g e   c o n t a i n e r   I D   o f   f r a g m e n t   
-  
-  & F a i l e d   t o   b i n d   E d i t O p t i o n s M e n u F r a g m e n t 
-  
-  & F a i l e d   t o   b i n d   M o r e O p t i o n s M e n u F r a g m e n t 
-  
-  & L a n d r o i d x / a p p c o m p a t / w i d g e t / S e a r c h V i e w ; 
-  
-  & L c o m / s p o t i f y / b a s e / j a v a / l o g g i n g / L o g g e r ; 
-  
-  & L c o m / s p o t i f y / c o n t e n t a g n o s t i c / v 2 / A u d i o ; 
-  
-  & L c o m / s p o t i f y / c o n t e n t a g n o s t i c / v 2 / C h a r t ; 
-  
-  & L c o m / s p o t i f y / c o n t e n t a g n o s t i c / v 2 / G e n r e ; 
-  
-  & L c o m / s p o t i f y / c o n t e n t a g n o s t i c / v 2 / I m a g e ; 
-  
-  & L c o m / s p o t i f y / c o n t e n t a g n o s t i c / v 2 / V i d e o ; 
-  
-  & L c o m / s p o t i f y / c o r e / h t t p / H t t p C o n n e c t i o n ; 
-  
-  & L c o m / s p o t i f y / c o s m o s / c o s m o s / R e s p o n s e K t ; 
-  
-  & L c o m / s p o t i f y / c o s m o s / r x r o u t e r / R x R o u t e r ; 
-  
-  & L c o m / s p o t i f y / d e c i p h e r / a g e n t / v 1 / A c t i o n ; 
-  
-  & L c o m / s p o t i f y / m o b i u s / M o b i u s L o o p $ L o g g e r ; 
-  
-  & L c o m / s p o t i f y / m o b i u s / a n d r o i d / L i v e Q u e u e ; 
-  
-  & L c o m / s p o t i f y / m u s i c / S p o t i f y A p p l i c a t i o n ; 
-  
-  & L c o m / s p o t i f y / p l a y e r / m o d e l / A u d i o S t r e a m ; 
-  
-  & L c o m / s p o t i f y / p l a y e r / m o d e l / C o n t e x t P a g e ; 
-  
-  & L c o m / s p o t i f y / p l a y e r / m o d e l / P l a y e r E r r o r ; 
-  
-  & L c o m / s p o t i f y / p l a y e r / m o d e l / P l a y e r Q u e u e ; 
-  
-  & L c o m / s p o t i f y / p l a y e r / m o d e l / P l a y e r S t a t e ; 
-  
-  & L c o m / s p o t i f y / t a p / s p o t o n / S p o t O n S e r v i c e ; 
-  
-  & R e c e i v e d   e r r o r   f r o m   L o g i n U p d a t e s   A P I :   
-  
-  & c o m . f a c e b o o k . s d k . U S E R _ S E T T I N G S _ B I T M A S K 
-  
-  & c o m . s p o t i f y . m u s i c . f e a t u r e . w i d g e t . P A U S E 
-  
-  & c o m . s p o t i f y . p a r t n e r a s s i s t a n t s a i . s a m p l e 
-  
-  & h t t p s : / / w w w . s p o t i f y . c o m / w r a p p e d - s h a r e / 
-  
-  & s p o t i f y : i n t e r n a l : s n o o z e - r e c o m m e n d a t i o n 
-  
-  ' ( L c o m / s p o t i f y / c o r e / h t t p / H t t p R e s p o n s e ; ) V 
-  
-  ' ( L c o m / s p o t i f y / c o s m o s / c o s m o s / R e s p o n s e ; ) V 
-  
-  ' ( L c o m / s p o t i f y / c o s m o s / c o s m o s / R e s p o n s e ; ) Z 
-  
-  ' E R R O R _ C O D E _ I O _ I N V A L I D _ H T T P _ C O N T E N T _ T Y P E 
-  
-  ' E n d   o f   S p o t i f y   u r i   r e a c h e d   u n e x p e c t e d l y 
-  
-  ' H I D D E N _ F R O M _ H O M E _ I T E M _ D A T A _ F I E L D _ N U M B E R 
-  
-  ' L c o m / s p o t i f y / c a s i t a / v 1 / r e s o l v e d / B a n n e r ; 
-  
-  ' L c o m / s p o t i f y / c o n n e c t / e s p e r a n t o / p r o t o / a ; 
-  
-  ' L c o m / s p o t i f y / c o n n e c t / e s p e r a n t o / p r o t o / b ; 
-  
-  ' L c o m / s p o t i f y / c o n n e c t / e s p e r a n t o / p r o t o / c ; 
-  
-  ' L c o m / s p o t i f y / c o n n e c t / e s p e r a n t o / p r o t o / d ; 
-  
-  ' L c o m / s p o t i f y / c o n n e c t i v i t y / a u t h / S e s s i o n ; 
-  
-  ' L c o m / s p o t i f y / c o n t e n t a g n o s t i c / v 2 / R a t i n g ; 
-  
-  ' L c o m / s p o t i f y / c o r e / h t t p / H e a d e r S a n i t i z e r ; 
-  
-  ' L c o m / s p o t i f y / m o b i u s / M o b i u s L o o p $ B u i l d e r ; 
-  
-  ' L c o m / s p o t i f y / m o b i u s / M o b i u s L o o p $ F a c t o r y ; 
-  
-  ' L c o m / s p o t i f y / m o b i u s / e x t r a s / S L F 4 J L o g g e r ; 
-  
-  ' L c o m / s p o t i f y / m o b i u s / f u n c t i o n s / C o n s u m e r ; 
-  
-  ' L c o m / s p o t i f y / m o b i u s / f u n c t i o n s / P r o d u c e r ; 
-  
-  ' L c o m / s p o t i f y / m o b i u s / r u n n e r s / W o r k R u n n e r ; 
-  
-  ' L c o m / s p o t i f y / m o b i u s / r x 3 / R x C o n n e c t a b l e s ; 
-  
-  ' L c o m / s p o t i f y / m o b i u s / r x 3 / R x E v e n t S o u r c e s ; 
-  
-  ' L c o m / s p o t i f y / m u s i c / S p o t i f y M a i n A c t i v i t y ; 
-  
-  ' L c o m / s p o t i f y / o f f l i n e _ e s p e r a n t o / p r o t o / c ; 
-  
-  ' L c o m / s p o t i f y / p l a y e r / m o d e l / C o n t e x t T r a c k ; 
-  
-  ' L c o m / s p o t i f y / p l a y e r / m o d e l / R e s t r i c t i o n s ; 
-  
-  ' L c o m / s p o t i f y / p l a y e r / m o d e l / S u p p r e s s i o n s ; 
-  
-  ' L c o m / s p o t i f y / w r a p p e d / v 1 / p r o t o / R i v e F o n t ; 
-  
-  ' R e s e t t i n g   c l i e n t   t o   d i s c o n n e c t e d   s t a t e . 
-  
-  ' a u t h _ a p i _ c r e d e n t i a l s _ g e t _ s i g n _ i n _ i n t e n t 
-  
-  ' c o m . g o o g l e . a n d r o i d . g o o g l e q u i c k s e a r c h b o x 
-  
-  ' c o m . g o o g l e . a n d r o i d . w e a r a b l e . a p i . v e r s i o n 
-  
-  ' c o m . s p o t i f y . m u s i c . f e a t u r e . w i d g e t . R E S U M E 
-  
-  ' s p e e c h l e s s / v 1 / h i e r a r c h y / s e t t i n g s / u n m u t e 
-  
-  ' s p o t i f y . a d s . e s p e r a n t o . p r o t o . D e v i c e S t a t e 
-  
-  ' s p o t i f y . o f f l i n e _ e s p e r a n t o . p r o t o . O f f l i n e 
-  
-  ' s p o t i f y : a g e - a s s u r a n c e : u n d e r a g e : b l o c k i n g 
-  
-  ' s p o t i f y : p l a y l i s t : 3 7 i 9 d Q Z F 1 F 5 p 3 r m i W P I Y g Z 
-  
-  ' s p o t i f y : p l a y l i s t : 3 7 i 9 d Q Z F 1 F g n T B f U l z k e K t 
-  
-  ' s p o t i f y : p l a y l i s t : 3 7 i 9 d Q Z F 1 F o y Q G y i n u u v R u 
-  
-  (   i s   n o t   c u r r e n t l y   i n   t h e   F r a g m e n t M a n a g e r 
-  
-  (   n o t   a s s o c i a t e d   w i t h   a   f r a g m e n t   m a n a g e r . 
-  
-  ( ( ) L c o m / s p o t i f y / c o s m o s / r x r o u t e r / R x R o u t e r ; 
-  
-  ( I L c o m / s p o t i f y / c o n t e n t d e l i v e r y / m e d i a p r o c e s s i n g / P r o c e s s i n g M o d e ; ) L c o m / s p o t i f y / c o n t e n t d e l i v e r y / m e d i a p r o c e s s i n g / C r e a t e P r o c e s s o r R e s u l t ; 
-  
-  ( L a n d r o i d / a p p / A c t i v i t y M a n a g e r $ M e m o r y I n f o ; 
-  
-  ( L c o m / s p o t i f y / c a s i t a / v 1 / r e s o l v e d / A n c h o r s ; 
-  
-  

## Appendix B — Inventory occurrence sample (base.apk, first 200)

See REA inspect_analysis_view evidence ev_d928c5d6 (page 0, 40 items). Full 4211 occurrences paged via REA.

## Appendix C — Property files present (base.apk)

- billing.properties
- common.properties
- core-common.properties
- crossdeviceprompt.properties
- engage-core.properties
- feature-delivery.properties
- firebase-encoders-proto.properties
- googleid.properties
- image.properties
- integrity.properties
- meet-addons.properties
- play-services-ads-identifier.properties
- play-services-auth-api-phone.properties
- play-services-auth-base.properties
- play-services-auth.properties
- play-services-base.properties
- play-services-basement.properties
- play-services-cast-framework.properties
- play-services-cast.properties
- play-services-cronet.properties
- play-services-flags.properties
- play-services-location.properties
- play-services-maps.properties
- play-services-mlkit-text-recognition-common.properties
- play-services-mlkit-text-recognition.properties
- play-services-recaptchabase.properties
- play-services-stats.properties
- play-services-tasks.properties
- play-services-wearable.properties
- recaptcha.properties
- vision-common.properties
- vision-interfaces.properties
- car-app-api.level

## Appendix D — Deep-analysis limitation notes (Android)

- Limitation note 1: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 2: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 3: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 4: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 5: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 6: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 7: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 8: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 9: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 10: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 11: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 12: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 13: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 14: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 15: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 16: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 17: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 18: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 19: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 20: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 21: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 22: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 23: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 24: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 25: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 26: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 27: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 28: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 29: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 30: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 31: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 32: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 33: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 34: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 35: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 36: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 37: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 38: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 39: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 40: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 41: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 42: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 43: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 44: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 45: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 46: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 47: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 48: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 49: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 50: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 51: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 52: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 53: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 54: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 55: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 56: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 57: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 58: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 59: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 60: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 61: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 62: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 63: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 64: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 65: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 66: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 67: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 68: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 69: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 70: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 71: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 72: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 73: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 74: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 75: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 76: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 77: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 78: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 79: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 80: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 81: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 82: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 83: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 84: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 85: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 86: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 87: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 88: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 89: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 90: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 91: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 92: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 93: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 94: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 95: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 96: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 97: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 98: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 99: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 100: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 101: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 102: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 103: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 104: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 105: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 106: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 107: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 108: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 109: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 110: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 111: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 112: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 113: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 114: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 115: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 116: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 117: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 118: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 119: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 120: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 121: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 122: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 123: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 124: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 125: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 126: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 127: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 128: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 129: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 130: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 131: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 132: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 133: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 134: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 135: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 136: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 137: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 138: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 139: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 140: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 141: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 142: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 143: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 144: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 145: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 146: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 147: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 148: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 149: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 150: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 151: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 152: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 153: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 154: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 155: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 156: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 157: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 158: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 159: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 160: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 161: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 162: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 163: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 164: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 165: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 166: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 167: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 168: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 169: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 170: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 171: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 172: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 173: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 174: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 175: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 176: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 177: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 178: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 179: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 180: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 181: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 182: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 183: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 184: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 185: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 186: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 187: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 188: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 189: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 190: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 191: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 192: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 193: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 194: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 195: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 196: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 197: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 198: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 199: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 200: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 201: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 202: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 203: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 204: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 205: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 206: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 207: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 208: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 209: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 210: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 211: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 212: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 213: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 214: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 215: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 216: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 217: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 218: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 219: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 220: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 221: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 222: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 223: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 224: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 225: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 226: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 227: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 228: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 229: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 230: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 231: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 232: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 233: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 234: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 235: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 236: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 237: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 238: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 239: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 240: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 241: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 242: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 243: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 244: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 245: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 246: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 247: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 248: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 249: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 250: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 251: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 252: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 253: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 254: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 255: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 256: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 257: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 258: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 259: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 260: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 261: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 262: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 263: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 264: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 265: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 266: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 267: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 268: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 269: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 270: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 271: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 272: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 273: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 274: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 275: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 276: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 277: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 278: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 279: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 280: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 281: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 282: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 283: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 284: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 285: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 286: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 287: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 288: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 289: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 290: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 291: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 292: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 293: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 294: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 295: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 296: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 297: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 298: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 299: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 300: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 301: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 302: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 303: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 304: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 305: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 306: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 307: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 308: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 309: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 310: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 311: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 312: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 313: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 314: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 315: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 316: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 317: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 318: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 319: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 320: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 321: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 322: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 323: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 324: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 325: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 326: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 327: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 328: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 329: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 330: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 331: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 332: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 333: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 334: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 335: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 336: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 337: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 338: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 339: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 340: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 341: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 342: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 343: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 344: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 345: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 346: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 347: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 348: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 349: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 350: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 351: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 352: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 353: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 354: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 355: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 356: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 357: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 358: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 359: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 360: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 361: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 362: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 363: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 364: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 365: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 366: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 367: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 368: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 369: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 370: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 371: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 372: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 373: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 374: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 375: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 376: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 377: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 378: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 379: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 380: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 381: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 382: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 383: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 384: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 385: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 386: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 387: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 388: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 389: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 390: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 391: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 392: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 393: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 394: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 395: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 396: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 397: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 398: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 399: without JADX/aapt, source and resources remain undecoded; behavior not executed.
- Limitation note 400: without JADX/aapt, source and resources remain undecoded; behavior not executed.


## Appendix E — UI details (Android, extracted resource inventory)

### res (0 files, 50 dirs)


### res\anim (0 files, 0 dirs)


### res\anim-v21 (0 files, 0 dirs)


### res\animator (0 files, 0 dirs)


### res\animator-v21 (0 files, 0 dirs)


### res\color (0 files, 0 dirs)


### res\color-night-v8 (0 files, 0 dirs)


### res\color-v23 (0 files, 0 dirs)


### res\color-v31 (0 files, 0 dirs)


### res\drawable (0 files, 0 dirs)


### res\drawable-hdpi-v4 (0 files, 0 dirs)


### res\drawable-land (0 files, 0 dirs)


### res\drawable-ldrtl (0 files, 0 dirs)


### res\drawable-nodpi-v4 (0 files, 0 dirs)


### res\drawable-v11 (0 files, 0 dirs)


### res\drawable-v21 (0 files, 0 dirs)


### res\drawable-v23 (0 files, 0 dirs)


### res\drawable-v31 (0 files, 0 dirs)


### res\drawable-watch-v20 (0 files, 0 dirs)


### res\drawable-xhdpi-v4 (0 files, 0 dirs)


### res\drawable-xxhdpi-v4 (0 files, 0 dirs)


### res\drawable-xxxhdpi-v4 (0 files, 0 dirs)


### res\font (0 files, 0 dirs)


### res\font-v29 (0 files, 0 dirs)


### res\interpolator (0 files, 0 dirs)


### res\interpolator-v21 (0 files, 0 dirs)


### res\layout (0 files, 0 dirs)


### res\layout-h450dp-v13 (0 files, 0 dirs)


### res\layout-h480dp-v13 (0 files, 0 dirs)


### res\layout-h600dp-v13 (0 files, 0 dirs)


### res\layout-h740dp-v13 (0 files, 0 dirs)


### res\layout-land (0 files, 0 dirs)


### res\layout-sw600dp-v13 (0 files, 0 dirs)


### res\layout-v26 (0 files, 0 dirs)


### res\layout-v31 (0 files, 0 dirs)


### res\layout-v33 (0 files, 0 dirs)


### res\layout-w1400dp-v13 (0 files, 0 dirs)


### res\layout-w600dp-h528dp-v13 (0 files, 0 dirs)


### res\layout-w840dp-v13 (0 files, 0 dirs)


### res\layout-watch-v20 (0 files, 0 dirs)


### res\mipmap-anydpi-v21 (0 files, 0 dirs)


### res\mipmap-anydpi-v26 (0 files, 0 dirs)


### res\mipmap-hdpi-v4 (0 files, 0 dirs)


### res\mipmap-mdpi-v4 (0 files, 0 dirs)


### res\mipmap-xhdpi-v4 (0 files, 0 dirs)


### res\mipmap-xxhdpi-v4 (0 files, 0 dirs)


### res\mipmap-xxxhdpi-v4 (0 files, 0 dirs)


### res\navigation (0 files, 0 dirs)


### res\raw (0 files, 0 dirs)


### res\xml (0 files, 0 dirs)


### res\xml-v25 (0 files, 0 dirs)


### assets (top-level files)


- Android UI detail note 1: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 2: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 3: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 4: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 5: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 6: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 7: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 8: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 9: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 10: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 11: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 12: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 13: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 14: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 15: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 16: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 17: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 18: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 19: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 20: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 21: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 22: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 23: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 24: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 25: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 26: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 27: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 28: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 29: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 30: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 31: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 32: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 33: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 34: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 35: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 36: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 37: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 38: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 39: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 40: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 41: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 42: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 43: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 44: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 45: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 46: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 47: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 48: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 49: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 50: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 51: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 52: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 53: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 54: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 55: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 56: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 57: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 58: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 59: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 60: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 61: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 62: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 63: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 64: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 65: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 66: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 67: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 68: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 69: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 70: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 71: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 72: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 73: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 74: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 75: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 76: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 77: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 78: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 79: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 80: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 81: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 82: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 83: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 84: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 85: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 86: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 87: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 88: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 89: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 90: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 91: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 92: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 93: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 94: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 95: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 96: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 97: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 98: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 99: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 100: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 101: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 102: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 103: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 104: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 105: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 106: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 107: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 108: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 109: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 110: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 111: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 112: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 113: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 114: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 115: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 116: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 117: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 118: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 119: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 120: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 121: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 122: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 123: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 124: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 125: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 126: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 127: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 128: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 129: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 130: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 131: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 132: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 133: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 134: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 135: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 136: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 137: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 138: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 139: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 140: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 141: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 142: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 143: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 144: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 145: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 146: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 147: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 148: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 149: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 150: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 151: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 152: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 153: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 154: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 155: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 156: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 157: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 158: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 159: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 160: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 161: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 162: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 163: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 164: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 165: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 166: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 167: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 168: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 169: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 170: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 171: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 172: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 173: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 174: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 175: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 176: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 177: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 178: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 179: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 180: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 181: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 182: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 183: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 184: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 185: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 186: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 187: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 188: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 189: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 190: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 191: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 192: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 193: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 194: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 195: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 196: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 197: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 198: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 199: resource binary; decoded names only, values unknown without aapt.
- Android UI detail note 200: resource binary; decoded names only, values unknown without aapt.
